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

    // 调度时间提醒，返回 notificationId
    // pairedLocations 不为空时表示配对模式：时间到达后需检查用户是否在指定位置才发通知
    func scheduleTimeReminder(
        counterName: String,
        reminder: TimeReminder,
        pairedLocations: [LocationReminder] = []
    ) async -> String? {
        guard reminder.isEnabled else { return nil }

        let content = UNMutableNotificationContent()
        content.title = "计数提醒"
        content.body = "该为「\(counterName)」记一笔了"
        content.sound = .default

        // 配对模式：将位置信息存入 userInfo，由 NotificationDelegate 在前台进行位置检查
        if !pairedLocations.isEmpty {
            content.userInfo = ["pairedLocations": pairedLocations.map { loc in
                ["lat": loc.latitude, "lng": loc.longitude, "radius": loc.radius]
            }]
        }

        var dateComponents = DateComponents()
        dateComponents.hour = reminder.hour
        dateComponents.minute = reminder.minute

        switch reminder.frequency {
        case .daily:
            break  // 仅设置 hour/minute，每天触发
        case .weekly:
            dateComponents.weekday = Calendar.current.component(.weekday, from: Date())
        case .monthly:
            dateComponents.day = Calendar.current.component(.day, from: Date())
        }

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let identifier = UUID().uuidString
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        do {
            try await UNUserNotificationCenter.current().add(request)
            return identifier
        } catch {
            return nil
        }
    }

    func cancelNotification(withId id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    func cancelAllNotifications(for config: ReminderConfig?) {
        guard let config = config else { return }
        let ids = config.triggerConditions.compactMap { $0.notificationId }
        if !ids.isEmpty {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        }
    }
}
