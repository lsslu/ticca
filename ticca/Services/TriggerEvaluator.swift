//
//  TriggerEvaluator.swift
//  ticca
//
//  统一仲裁中心：时间 tick / 围栏进入 / reconcile 三个入口走同一套真值表
//

import Foundation
import SwiftData
import CoreLocation
import UserNotifications

// MARK: - 中间状态枚举

enum TimeStatus: Equatable {
    case satisfied                 // 当前时刻在 [T - windowBefore, T + windowAfter] 内
    case missed                    // 已超过 T + windowAfter
    case pending(at: Date)         // 尚未到 T - windowBefore，参数是窗口起点
}

enum LocationStatus: Equatable {
    case inside
    case outside
    case unknown
}

enum EvaluatorResult {
    case show
    case suppress
    case timeout
}

// MARK: - TriggerEvaluator

@MainActor
final class TriggerEvaluator {
    static let shared = TriggerEvaluator()

    /// 由 ticcaApp 在启动时注入
    weak var modelContainer: ModelContainer?

    private init() {}

    // MARK: 外部入口

    /// App 启动 / 进入前台时调用：构建索引、reconcile 全量 condition
    func reconcileAll(counters: [Counter]) async {
        var configsToWrite: [Counter] = []

        for counter in counters {
            guard var config = counter.reminderConfig else { continue }
            var changed = false

            // 1. 清理 once 类型 condition：已 consumed 或已过期
            let before = config.triggerConditions.count
            config.triggerConditions.removeAll { tc in
                let isExpired = (tc.expiresAt != nil && tc.expiresAt! < Date())
                let isConsumed = (tc.consumedAt != nil)
                return tc.frequency == .once && (isExpired || isConsumed)
            }
            if config.triggerConditions.count != before {
                changed = true
            }

            // 2. 对每个启用且有效的 condition 走一次评估
            for i in config.triggerConditions.indices {
                let cond = config.triggerConditions[i]
                guard cond.isEnabled, cond.isValid else { continue }
                await evaluate(cond, counter: counter, source: .reconcile)
            }

            if changed {
                counter.reminderConfig = config
                configsToWrite.append(counter)
            }
        }
    }

    /// 围栏进入回调入口
    func handleRegionEntry(conditionId: String) async {
        guard let (counter, _, cond) = findCondition(conditionId: conditionId) else { return }
        await evaluate(cond, counter: counter, source: .regionEntry)
    }

    /// willPresent 拦截入口，2 秒预算内做完仲裁
    func evaluateOnTimeTick(
        conditionId: String,
        regionId: String,
        needsLocationCheck: Bool
    ) async -> EvaluatorResult {
        guard let (counter, _, cond) = findCondition(conditionId: conditionId) else {
            return .suppress
        }

        // 已在当前窗口触发过 → 抑制
        if alreadyFiredInCurrentWindow(cond) {
            return .suppress
        }

        let now = Date()
        let timeS = Self.timeStatus(cond.time, frequency: cond.frequency, now: now)

        // 无需查位置：直接按真值表判定
        if !needsLocationCheck {
            let locS: LocationStatus = (cond.location == .none) ? .inside : .unknown
            if Self.shouldFire(time: timeS, location: locS, combinator: cond.combinator, missPolicy: cond.missPolicy) {
                markFired(conditionId: conditionId, counter: counter)
                return .show
            }
            return .suppress
        }

        // 需要查位置：2 秒超时窗
        let stateResult = await withTimeout(seconds: 2.0) { () -> LocationStatus in
            await self.locationStatus(condition: cond)
        }
        switch stateResult {
        case .completed(let locS):
            if Self.shouldFire(time: timeS, location: locS, combinator: cond.combinator, missPolicy: cond.missPolicy) {
                markFired(conditionId: conditionId, counter: counter)
                return .show
            }
            return .suppress
        case .timedOut:
            return .timeout
        }
    }

    /// 通知触发后续期下一次 tick
    func scheduleNext(conditionId: String) async {
        guard let (counter, idx, cond) = findCondition(conditionId: conditionId) else { return }
        guard cond.isEnabled, cond.hasTimeConstraint else { return }
        guard cond.frequency != .once else { return }  // once 不续期

        let nextFire = Self.nextFireTime(for: cond, after: Date())
        guard let nextFire = nextFire else { return }

        let nid = await NotificationService.shared.scheduleOneShot(
            conditionId: cond.id,
            counterName: counter.name,
            regionId: cond.regionId,
            combinator: cond.combinator,
            needsLocationCheck: cond.needsLocationCheck,
            fireAt: nextFire,
            windowAfter: cond.timeWindowAfter
        )

        if let nid = nid {
            guard var config = counter.reminderConfig else { return }
            if config.triggerConditions.indices.contains(idx) {
                config.triggerConditions[idx].pendingNotificationIds.append(nid)
                counter.reminderConfig = config
            }
        }
    }

    /// 降级路径：超时时立即发一条带"位置未确认"标注的新通知
    func fireWithUncertainTag(conditionId: String) async {
        guard let (counter, _, _) = findCondition(conditionId: conditionId) else { return }
        _ = await NotificationService.shared.fireImmediate(
            conditionId: conditionId,
            counterName: counter.name,
            suffix: "（位置未确认）"
        )
        markFired(conditionId: conditionId, counter: counter)
    }

    // MARK: 评估核心

    enum Source { case timeTick; case regionEntry; case reconcile }

    /// 完整评估 + 触发分支
    func evaluate(_ condition: TriggerCondition, counter: Counter, source: Source) async {
        guard condition.isEnabled, condition.isValid else { return }
        if alreadyFiredInCurrentWindow(condition) { return }

        let now = Date()
        let timeS = Self.timeStatus(condition.time, frequency: condition.frequency, now: now)
        let locS = await locationStatus(condition: condition)

        if Self.shouldFire(time: timeS, location: locS, combinator: condition.combinator, missPolicy: condition.missPolicy) {
            _ = await NotificationService.shared.fireImmediate(
                conditionId: condition.id,
                counterName: counter.name
            )
            markFired(conditionId: condition.id, counter: counter)
        }
    }

    // MARK: 纯函数：真值表

    nonisolated static func shouldFire(
        time: TimeStatus,
        location: LocationStatus,
        combinator: Combinator,
        missPolicy: MissPolicy
    ) -> Bool {
        switch combinator {
        case .or:
            if case .satisfied = time { return true }
            if case .inside = location { return true }
            return false
        case .and:
            switch (time, location) {
            case (.satisfied, .inside):
                return true
            case (.missed, .inside):
                return missPolicy == .fireOnLateEntry
            default:
                return false
            }
        }
    }

    // MARK: 纯函数：时间状态

    nonisolated static func timeStatus(_ time: TimeConstraint, frequency: ReminderFrequency, now: Date) -> TimeStatus {
        switch time {
        case .none:
            return .satisfied
        case .instant(let dc, let before, let after):
            let cal = Calendar.current
            var match = Self.buildMatchComponents(dc: dc, frequency: frequency)

            // 找最近的过去匹配时刻
            let prev = cal.nextDate(after: now, matching: match, matchingPolicy: .nextTime, direction: .backward)
            if let prev = prev, now >= prev && now <= prev.addingTimeInterval(after) {
                return .satisfied
            }

            // 找最近的未来匹配时刻
            let next = cal.nextDate(after: now, matching: match, matchingPolicy: .nextTime)
            if let next = next {
                if now >= next.addingTimeInterval(-before) && now <= next {
                    return .satisfied
                }
                if now < next.addingTimeInterval(-before) {
                    return .pending(at: next.addingTimeInterval(-before))
                }
            }
            return .missed
        case .range(let from, let to):
            // 简化实现：只处理同日 to.hour > from.hour 的情况
            let cal = Calendar.current
            let matchFrom = Self.buildMatchComponents(dc: from, frequency: frequency)
            let matchTo = Self.buildMatchComponents(dc: to, frequency: frequency)

            let prevFrom = cal.nextDate(after: now, matching: matchFrom, matchingPolicy: .nextTime, direction: .backward)
            if let pf = prevFrom {
                let toAfterPf = cal.nextDate(after: pf, matching: matchTo, matchingPolicy: .nextTime)
                if let tap = toAfterPf, now >= pf && now <= tap {
                    return .satisfied
                }
            }
            let nextFrom = cal.nextDate(after: now, matching: matchFrom, matchingPolicy: .nextTime)
            if let nf = nextFrom {
                return .pending(at: nf)
            }
            return .missed
        }
    }

    nonisolated private static func buildMatchComponents(dc: DateComponents, frequency: ReminderFrequency) -> DateComponents {
        var c = DateComponents()
        c.hour = dc.hour
        c.minute = dc.minute
        c.second = 0
        switch frequency {
        case .daily, .once:
            break
        case .weekly:
            if let w = dc.weekday { c.weekday = w }
        case .monthly:
            if let d = dc.day { c.day = d }
        }
        return c
    }

    // MARK: 纯函数：下一次触发时间

    /// 调度一次性通知的 fireAt：下一个 T - windowBefore
    nonisolated static func nextFireTime(for condition: TriggerCondition, after t: Date) -> Date? {
        let cal = Calendar.current
        switch condition.time {
        case .none:
            return nil
        case .instant(let dc, let before, _):
            let match = buildMatchComponents(dc: dc, frequency: condition.frequency)
            guard let nextT = cal.nextDate(after: t, matching: match, matchingPolicy: .nextTime) else { return nil }
            // once 频率，且 expiresAt 已过 → 不再调度
            if condition.frequency == .once {
                if let exp = condition.expiresAt, exp < t { return nil }
            }
            return nextT.addingTimeInterval(-before)
        case .range(let from, _):
            let match = buildMatchComponents(dc: from, frequency: condition.frequency)
            return cal.nextDate(after: t, matching: match, matchingPolicy: .nextTime)
        }
    }

    // MARK: 位置状态查询

    private func locationStatus(condition: TriggerCondition) async -> LocationStatus {
        switch condition.location {
        case .none:
            return .inside
        case .inside:
            guard let rid = condition.regionId else { return .unknown }
            let state = await LocationService.shared.currentState(for: rid)
            switch state {
            case .inside: return .inside
            case .outside: return .outside
            case .unknown: return .unknown
            @unknown default: return .unknown
            }
        }
    }

    // MARK: 去重

    private func alreadyFiredInCurrentWindow(_ condition: TriggerCondition) -> Bool {
        guard let last = condition.lastFiredAt else { return false }
        let cal = Calendar.current
        let now = Date()
        switch condition.frequency {
        case .daily:
            return cal.isDate(last, inSameDayAs: now)
        case .weekly:
            return cal.isDate(last, equalTo: now, toGranularity: .weekOfYear)
        case .monthly:
            return cal.isDate(last, equalTo: now, toGranularity: .month)
        case .once:
            return condition.consumedAt != nil
        }
    }

    // MARK: 状态写回

    private func markFired(conditionId: String, counter: Counter) {
        guard var config = counter.reminderConfig else { return }
        guard let idx = config.triggerConditions.firstIndex(where: { $0.id == conditionId }) else { return }
        config.triggerConditions[idx].lastFiredAt = Date()
        if config.triggerConditions[idx].frequency == .once {
            config.triggerConditions[idx].consumedAt = Date()
        }
        counter.reminderConfig = config
    }

    // MARK: 反查 condition

    /// 从 SwiftData 全量扫描查找 condition；单用户应用规模可控（<100 条），O(n) 可接受
    func findCondition(conditionId: String) -> (counter: Counter, index: Int, condition: TriggerCondition)? {
        guard let container = modelContainer else { return nil }
        let descriptor = FetchDescriptor<Counter>()
        guard let counters = try? container.mainContext.fetch(descriptor) else { return nil }
        for counter in counters {
            guard let config = counter.reminderConfig else { continue }
            for (i, tc) in config.triggerConditions.enumerated() where tc.id == conditionId {
                return (counter, i, tc)
            }
        }
        return nil
    }
}

// MARK: - TriggerCondition 运行时辅助属性

extension TriggerCondition {
    var hasTimeConstraint: Bool {
        if case .none = time { return false }
        return true
    }

    var hasLocationConstraint: Bool {
        if case .none = location { return false }
        return true
    }

    var timeWindowAfter: TimeInterval {
        if case .instant(_, _, let a) = time { return a }
        return 0
    }

    var timeWindowBefore: TimeInterval {
        if case .instant(_, let b, _) = time { return b }
        return 0
    }

    var needsLocationCheck: Bool {
        combinator == .and && hasLocationConstraint
    }
}

// MARK: - withTimeout 工具

enum TimeoutResult<T> {
    case completed(T)
    case timedOut
}

func withTimeout<T: Sendable>(seconds: Double, operation: @Sendable @escaping () async -> T) async -> TimeoutResult<T> {
    await withTaskGroup(of: TimeoutResult<T>.self) { group in
        group.addTask {
            let v = await operation()
            return .completed(v)
        }
        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return .timedOut
        }
        let first = await group.next()!
        group.cancelAll()
        return first
    }
}
