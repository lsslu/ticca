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

    /// 设置计数器的所有提醒（先取消旧的，再根据触发条件列表重新注册）
    func setupReminders(for counter: Counter) async {
        guard var config = counter.reminderConfig else { return }

        // 1. 取消旧提醒
        await cancelReminders(config: counter.reminderConfig)

        // 2. 重新计算触发条件列表（笛卡尔积或单独条件）
        config.recomputeTriggerConditions()

        // 3. 注册所有启用的位置提醒的地理围栏
        //    isPaired = 该位置出现在任何时间+位置配对条件中
        for i in config.locationReminders.indices {
            var reminder = config.locationReminders[i]
            if reminder.isEnabled {
                let isPaired = config.triggerConditions.contains {
                    $0.locationReminderIndex == i && $0.timeReminderIndex != nil
                }
                let regionId = locationService.monitorRegion(
                    counterName: counter.name,
                    reminder: reminder,
                    isPaired: isPaired
                )
                reminder.regionId = regionId
            } else {
                reminder.regionId = nil
            }
            config.locationReminders[i] = reminder
        }

        // 4. 遍历触发条件列表，为各条件注册系统通知
        for i in config.triggerConditions.indices {
            var condition = config.triggerConditions[i]

            if let ti = condition.timeReminderIndex {
                let timeReminder = config.timeReminders[ti]
                if let li = condition.locationReminderIndex {
                    // 时间+位置配对条件：时间到达时检查是否在指定位置
                    let locationReminder = config.locationReminders[li]
                    condition.notificationId = await notificationService.scheduleTimeReminder(
                        counterName: counter.name,
                        reminder: timeReminder,
                        pairedLocations: [locationReminder]
                    )
                } else {
                    // 仅时间条件：直接触发
                    condition.notificationId = await notificationService.scheduleTimeReminder(
                        counterName: counter.name,
                        reminder: timeReminder,
                        pairedLocations: []
                    )
                }
            }
            // 仅位置条件（timeReminderIndex == nil）：地理围栏已在步骤3注册，无需额外注册通知

            config.triggerConditions[i] = condition
        }

        // 5. 更新计数器配置
        counter.reminderConfig = config
    }

    /// 取消所有提醒
    func cancelReminders(config: ReminderConfig?) {
        notificationService.cancelAllNotifications(for: config)
        locationService.stopAllMonitoring(for: config)
    }

    /// 恢复所有计数器的位置提醒监控（应用启动时调用）
    func restoreLocationMonitoring(counters: [Counter]) {
        for counter in counters {
            guard let config = counter.reminderConfig else { continue }
            for (i, reminder) in config.locationReminders.enumerated() where reminder.isEnabled {
                if let regionId = reminder.regionId {
                    let isMonitoring = locationService.locationManager.monitoredRegions.contains {
                        $0.identifier == regionId
                    }
                    if !isMonitoring {
                        let isPaired = config.triggerConditions.contains {
                            $0.locationReminderIndex == i && $0.timeReminderIndex != nil
                        }
                        _ = locationService.monitorRegion(
                            counterName: counter.name,
                            reminder: reminder,
                            isPaired: isPaired
                        )
                    }
                }
            }
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
