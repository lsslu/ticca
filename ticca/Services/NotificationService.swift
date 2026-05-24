//
//  NotificationService.swift
//  ticca
//

import UserNotifications
import Foundation
import Combine

@MainActor
class NotificationService: NSObject, ObservableObject {
    static let shared = NotificationService()

    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private override init() {
        super.init()
        Task {
            await checkAuthorizationStatus()
        }
    }

    func checkAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            await checkAuthorizationStatus()
            return granted
        } catch {
            return false
        }
    }

    // MARK: - One-shot Scheduling

    /// 为指定触发条件调度一次性日历通知（用于"下一个时间点"的 tick）
    /// 返回 notification identifier，失败返回 nil
    func scheduleOneShot(
        conditionId: String,
        counterName: String,
        regionId: String?,
        combinator: Combinator,
        needsLocationCheck: Bool,
        fireAt: Date,
        windowAfter: TimeInterval
    ) async -> String? {
        let content = UNMutableNotificationContent()
        content.title = "提醒"
        content.body = "该为「\(counterName)」记一笔了"
        content.sound = .default
        content.userInfo = [
            "kind": "trigger",
            "conditionId": conditionId,
            "counterName": counterName,
            "regionId": regionId ?? "",
            "combinator": combinator.rawValue,
            "needsLocationCheck": needsLocationCheck,
            "scheduledFor": ISO8601DateFormatter().string(from: fireAt),
            "windowAfter": Int(windowAfter),
            "schemaV": 2
        ]

        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireAt)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let identifier = "tc_\(conditionId)_\(Int(fireAt.timeIntervalSince1970))"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        do {
            try await UNUserNotificationCenter.current().add(request)
            return identifier
        } catch {
            return nil
        }
    }

    /// 立即发送一条通知（用于围栏进入触发 / 迟到补提醒 / 降级路径）
    func fireImmediate(
        conditionId: String,
        counterName: String,
        suffix: String? = nil
    ) async -> String? {
        let content = UNMutableNotificationContent()
        content.title = "提醒"
        var body = "该为「\(counterName)」记一笔了"
        if let suffix = suffix { body += suffix }
        content.body = body
        content.sound = .default
        content.userInfo = [
            "kind": "trigger-immediate",
            "conditionId": conditionId,
            "schemaV": 2
        ]
        let identifier = "tc_imm_\(conditionId)_\(Int(Date().timeIntervalSince1970))"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
            return identifier
        } catch {
            return nil
        }
    }

    // MARK: - Cancellation

    func cancelNotifications(withIds ids: [String]) {
        guard !ids.isEmpty else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    func cancelAllPendingNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
