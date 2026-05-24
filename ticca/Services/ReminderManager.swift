//
//  ReminderManager.swift
//  ticca
//

import Foundation
import SwiftData
import Combine
import CoreLocation
import UserNotifications

@MainActor
class ReminderManager: ObservableObject {
    static let shared = ReminderManager()

    private let notificationService = NotificationService.shared
    private let locationService = LocationService.shared

    private init() {}

    /// 设置计数器的所有提醒：取消旧的、为每个有效启用的 condition 注册围栏 + 调度时间 tick
    func setupReminders(for counter: Counter) async {
        guard var config = counter.reminderConfig else { return }

        // 1. 取消旧提醒
        cancelReminders(config: counter.reminderConfig)

        // 2. 遍历 triggerConditions，逐个 arm
        for i in config.triggerConditions.indices {
            var cond = config.triggerConditions[i]

            // 重置运行时状态
            cond.regionId = nil
            cond.pendingNotificationIds = []

            guard cond.isEnabled, cond.isValid else {
                config.triggerConditions[i] = cond
                continue
            }

            // 围栏注册
            if case .inside(let lat, let lon, let r, _) = cond.location {
                cond.regionId = locationService.monitorRegion(
                    conditionId: cond.id,
                    latitude: lat,
                    longitude: lon,
                    radius: r
                )
            }

            // 时间 tick 调度
            if cond.hasTimeConstraint, cond.frequency != .once || cond.expiresAt == nil || cond.expiresAt! > Date() {
                if let fireAt = TriggerEvaluator.nextFireTime(for: cond, after: Date()) {
                    if let nid = await notificationService.scheduleOneShot(
                        conditionId: cond.id,
                        counterName: counter.name,
                        regionId: cond.regionId,
                        combinator: cond.combinator,
                        needsLocationCheck: cond.needsLocationCheck,
                        fireAt: fireAt,
                        windowAfter: cond.timeWindowAfter
                    ) {
                        cond.pendingNotificationIds.append(nid)
                    }
                }
            }

            config.triggerConditions[i] = cond
        }

        counter.reminderConfig = config
    }

    /// 取消该 config 下所有挂起通知和围栏
    func cancelReminders(config: ReminderConfig?) {
        guard let config = config else { return }
        var allIds: [String] = []
        for tc in config.triggerConditions {
            allIds += tc.pendingNotificationIds
            if let rid = tc.regionId {
                locationService.stopMonitoring(regionId: rid)
            }
        }
        notificationService.cancelNotifications(withIds: allIds)
    }

    /// 应用启动时恢复：由 TriggerEvaluator.reconcileAll 统一处理
    func restoreLocationMonitoring(counters: [Counter]) {
        Task {
            await TriggerEvaluator.shared.reconcileAll(counters: counters)
        }
    }

    /// 检查权限状态
    func checkPermissions() async -> (notification: Bool, location: Bool) {
        await notificationService.checkAuthorizationStatus()
        let notificationGranted = notificationService.authorizationStatus == .authorized
        let locationGranted = locationService.authorizationStatus == .authorizedWhenInUse ||
                              locationService.authorizationStatus == .authorizedAlways
        return (notificationGranted, locationGranted)
    }
}
