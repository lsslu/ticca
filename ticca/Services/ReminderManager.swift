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

    /// 设置计数器的所有提醒（先取消旧的，再注册新的）
    func setupReminders(for counter: Counter) async {
        guard var config = counter.reminderConfig else { return }

        // 取消旧提醒
        await cancelReminders(config: counter.reminderConfig)

        // 设置时间提醒
        var updatedTimeReminders: [TimeReminder] = []
        for var reminder in config.timeReminders {
            if reminder.isEnabled {
                let notificationId = await notificationService.scheduleTimeReminder(
                    counterName: counter.name,
                    reminder: reminder
                )
                reminder.notificationId = notificationId
            } else {
                reminder.notificationId = nil
            }
            updatedTimeReminders.append(reminder)
        }

        // 设置位置提醒
        var updatedLocationReminders: [LocationReminder] = []
        for var reminder in config.locationReminders {
            if reminder.isEnabled {
                let regionId = locationService.monitorRegion(
                    counterName: counter.name,
                    reminder: reminder
                )
                reminder.regionId = regionId
            } else {
                reminder.regionId = nil
            }
            updatedLocationReminders.append(reminder)
        }

        // 更新配置
        counter.reminderConfig = ReminderConfig(
            timeReminders: updatedTimeReminders,
            locationReminders: updatedLocationReminders
        )
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
            for reminder in config.locationReminders where reminder.isEnabled {
                if let regionId = reminder.regionId {
                    let isMonitoring = locationService.locationManager.monitoredRegions.contains {
                        $0.identifier == regionId
                    }
                    if !isMonitoring {
                        _ = locationService.monitorRegion(counterName: counter.name, reminder: reminder)
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
