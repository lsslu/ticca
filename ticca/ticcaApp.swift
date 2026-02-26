//
//  ticcaApp.swift
//  ticca
//
//  Created by lss on 2025/11/15.
//

import SwiftUI
import SwiftData
import UserNotifications
import CoreLocation

@main
struct ticcaApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Counter.self,
            CounterLog.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        // 设置通知代理，确保应用在前台时也能显示通知
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    restoreLocationMonitoring()
                }
        }
        .modelContainer(sharedModelContainer)
    }

    /// 应用启动时恢复地理围栏监控
    private func restoreLocationMonitoring() {
        let context = sharedModelContainer.mainContext
        let descriptor = FetchDescriptor<Counter>()
        if let counters = try? context.fetch(descriptor) {
            Task { @MainActor in
                ReminderManager.shared.restoreLocationMonitoring(counters: counters)
            }
        }
    }
}

/// 通知代理：处理前台通知展示和通知点击
class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    // 应用在前台时也显示通知
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo

        // 配对模式：时间提醒携带了配对的位置信息，需检查用户当前是否在指定位置
        if let locationDicts = userInfo["pairedLocations"] as? [[String: Double]] {
            guard let currentLocation = LocationService.shared.locationManager.location else {
                // 无法获取当前位置时，降级为普通显示
                completionHandler([.banner, .sound])
                return
            }
            let isAtPairedLocation = locationDicts.contains { dict in
                guard let lat = dict["lat"], let lng = dict["lng"], let radius = dict["radius"] else { return false }
                let target = CLLocation(latitude: lat, longitude: lng)
                return currentLocation.distance(from: target) <= radius
            }
            completionHandler(isAtPairedLocation ? [.banner, .sound] : [])
        } else {
            completionHandler([.banner, .sound])
        }
    }

    // 用户点击通知时的处理
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
}
