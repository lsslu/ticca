//
//  ticcaApp.swift
//  ticca
//
//  Created by lss on 2025/11/15.
//

import SwiftUI
import SwiftData
import UserNotifications

@main
struct ticcaApp: App {
    @Environment(\.scenePhase) private var scenePhase

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
        // 通知代理
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    // 注入容器、首启 reconcile
                    TriggerEvaluator.shared.modelContainer = sharedModelContainer
                    Task {
                        let ctx = sharedModelContainer.mainContext
                        if let counters = try? ctx.fetch(FetchDescriptor<Counter>()) {
                            await TriggerEvaluator.shared.reconcileAll(counters: counters)
                        }
                    }
                }
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task {
                    let ctx = sharedModelContainer.mainContext
                    if let counters = try? ctx.fetch(FetchDescriptor<Counter>()) {
                        await TriggerEvaluator.shared.reconcileAll(counters: counters)
                    }
                }
            }
        }
    }
}

/// 通知代理：willPresent 拦截做时间+位置仲裁
class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let info = notification.request.content.userInfo
        let kind = info["kind"] as? String

        // 非本系统通知 / 即时通知 → 直接放行
        guard kind == "trigger" else {
            completionHandler([.banner, .sound])
            return
        }

        let conditionId = info["conditionId"] as? String ?? ""
        let regionId = info["regionId"] as? String ?? ""
        let needsLocationCheck = info["needsLocationCheck"] as? Bool ?? false

        // 不需要查位置 → 立即展示，随后续期
        guard needsLocationCheck else {
            completionHandler([.banner, .sound, .badge])
            Task { @MainActor in
                await TriggerEvaluator.shared.scheduleNext(conditionId: conditionId)
            }
            return
        }

        // 需要查位置 → 2 秒预算
        Task { @MainActor in
            let result = await TriggerEvaluator.shared.evaluateOnTimeTick(
                conditionId: conditionId,
                regionId: regionId,
                needsLocationCheck: needsLocationCheck
            )
            switch result {
            case .show:
                completionHandler([.banner, .sound, .badge])
            case .suppress:
                completionHandler([])
            case .timeout:
                // 降级：吞掉原通知，新发一条带"位置未确认"后缀
                completionHandler([])
                await TriggerEvaluator.shared.fireWithUncertainTag(conditionId: conditionId)
            }
            // 无论分支，续期下一次 tick
            await TriggerEvaluator.shared.scheduleNext(conditionId: conditionId)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
}
