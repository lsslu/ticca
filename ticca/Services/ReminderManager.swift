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
        cancelReminders(config: counter.reminderConfig)

        // 2. 重新计算触发条件列表（笛卡尔积或单独条件）
        config.recomputeTriggerConditions()

        // 3. 注册所有启用的位置提醒的地理围栏
        for i in config.locationReminders.indices {
            var reminder = config.locationReminders[i]
            if reminder.isEnabled {
                let isPaired = config.triggerConditions.contains {
                    $0.locationReminderIndex == i && $0.timeReminderIndex != nil
                }
                let pairedTimeInfos = isPaired
                    ? buildPairedTimeInfos(config: config, locationIndex: i, counterName: counter.name)
                    : []

                let regionId = locationService.monitorRegion(
                    counterName: counter.name,
                    reminder: reminder,
                    isPaired: isPaired,
                    pairedTimeReminders: pairedTimeInfos
                )
                reminder.regionId = regionId
            } else {
                reminder.regionId = nil
            }
            config.locationReminders[i] = reminder
        }

        // 4. 遍历触发条件列表，仅为"纯时间"条件注册通知
        //    配对条件（时间+位置）由地理围栏进入/离开事件动态管理，此处不注册
        for i in config.triggerConditions.indices {
            var condition = config.triggerConditions[i]

            if let ti = condition.timeReminderIndex {
                if condition.locationReminderIndex != nil {
                    // 配对条件：不在此处调度，由 LocationService 围栏事件动态管理
                    condition.notificationId = nil
                } else {
                    // 纯时间条件：直接注册
                    let timeReminder = config.timeReminders[ti]
                    condition.notificationId = await notificationService.scheduleTimeReminder(
                        counterName: counter.name,
                        reminder: timeReminder
                    )
                }
            }
            // 纯位置条件（timeReminderIndex == nil）：地理围栏已在步骤3注册

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
                guard let regionId = reminder.regionId else { continue }

                let isPaired = config.triggerConditions.contains {
                    $0.locationReminderIndex == i && $0.timeReminderIndex != nil
                }
                let pairedTimeInfos = isPaired
                    ? buildPairedTimeInfos(config: config, locationIndex: i, counterName: counter.name)
                    : []

                let isMonitoring = locationService.locationManager.monitoredRegions.contains {
                    $0.identifier == regionId
                }

                if !isMonitoring {
                    // 围栏丢失（少见），重新注册
                    _ = locationService.monitorRegion(
                        counterName: counter.name,
                        reminder: reminder,
                        isPaired: isPaired,
                        pairedTimeReminders: pairedTimeInfos
                    )
                } else if isPaired {
                    // 围栏仍在监控中，检测用户是否在围栏内以补建时间通知
                    if let region = locationService.locationManager.monitoredRegions.first(where: {
                        $0.identifier == regionId
                    }) {
                        locationService.locationManager.requestState(for: region)
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

    // MARK: - Private Helpers

    /// 从 ReminderConfig 中构建指定位置索引关联的配对时间提醒信息
    private func buildPairedTimeInfos(
        config: ReminderConfig,
        locationIndex: Int,
        counterName: String
    ) -> [PairedTimeReminderInfo] {
        let pairedConditions = config.triggerConditions.filter {
            $0.locationReminderIndex == locationIndex && $0.timeReminderIndex != nil
        }
        return pairedConditions.compactMap { cond in
            guard let ti = cond.timeReminderIndex else { return nil }
            let tr = config.timeReminders[ti]
            return PairedTimeReminderInfo(
                counterName: counterName,
                hour: tr.hour,
                minute: tr.minute,
                frequency: tr.frequency
            )
        }
    }
}
