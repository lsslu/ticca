//
//  DebugView.swift
//  ticca
//

import SwiftUI
import UserNotifications

struct DebugView: View {
    @State private var showingDelayPicker = false
    @State private var delaySeconds: String = "5"
    @State private var permissionStatus: String = "检查中..."
    @State private var lastResult: String?

    var body: some View {
        Form {
            Section("权限状态") {
                HStack {
                    Text("通知权限")
                    Spacer()
                    Text(permissionStatus)
                        .foregroundColor(.secondary)
                }

                if permissionStatus == "未授权" || permissionStatus == "未请求" {
                    Button("请求通知权限") {
                        Task {
                            let granted = try? await UNUserNotificationCenter.current()
                                .requestAuthorization(options: [.alert, .sound, .badge])
                            await checkPermission()
                            lastResult = granted == true ? "权限已授予" : "权限被拒绝"
                        }
                    }
                }
            }

            Section("提醒调试") {
                Button {
                    triggerImmediately()
                } label: {
                    HStack {
                        Image(systemName: "bell.badge")
                            .foregroundColor(.blue)
                        Text("手动触发提醒")
                    }
                }

                Button {
                    showingDelayPicker = true
                } label: {
                    HStack {
                        Image(systemName: "timer")
                            .foregroundColor(.orange)
                        Text("延迟触发提醒")
                    }
                }
            }

            if let result = lastResult {
                Section("结果") {
                    Text(result)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("调试")
        .navigationBarTitleDisplayMode(.inline)
        .alert("设置延迟时间", isPresented: $showingDelayPicker) {
            TextField("秒数", text: $delaySeconds)
                .keyboardType(.numberPad)
            Button("确认") {
                if let seconds = Double(delaySeconds), seconds > 0 {
                    triggerWithDelay(seconds: seconds)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("输入延迟秒数后触发提醒通知")
        }
        .task {
            await checkPermission()
        }
    }

    private func checkPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized: permissionStatus = "已授权"
        case .denied: permissionStatus = "未授权"
        case .notDetermined: permissionStatus = "未请求"
        case .provisional: permissionStatus = "临时授权"
        case .ephemeral: permissionStatus = "临时授权"
        @unknown default: permissionStatus = "未知"
        }
    }

    private func triggerImmediately() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard settings.authorizationStatus == .authorized else {
                lastResult = "通知权限未授予，请先授予权限"
                return
            }

            let content = UNMutableNotificationContent()
            content.title = "调试提醒"
            content.body = "这是一条调试提醒通知"
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            do {
                try await UNUserNotificationCenter.current().add(request)
                lastResult = "通知已发送（立即触发）"
            } catch {
                lastResult = "发送失败：\(error.localizedDescription)"
            }
        }
    }

    private func triggerWithDelay(seconds: TimeInterval) {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard settings.authorizationStatus == .authorized else {
                lastResult = "通知权限未授予，请先授予权限"
                return
            }

            let content = UNMutableNotificationContent()
            content.title = "调试提醒"
            content.body = "这是一条延迟 \(Int(seconds)) 秒触发的调试提醒通知"
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: trigger
            )
            do {
                try await UNUserNotificationCenter.current().add(request)
                lastResult = "通知已调度（\(Int(seconds)) 秒后触发）"
            } catch {
                lastResult = "发送失败：\(error.localizedDescription)"
            }
        }
    }
}
