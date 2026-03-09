//
//  DebugView.swift
//  ticca
//

import SwiftUI
import UserNotifications
import CoreLocation

struct PendingNotificationInfo: Identifiable {
    let id: String
    let body: String
    let dateComponents: DateComponents
    let repeats: Bool
}

struct MonitoredRegionInfo: Identifiable {
    let id: String
    let center: CLLocationCoordinate2D
    let radius: CLLocationDistance
    let counterName: String
    let isPaired: Bool
    let activeNotificationCount: Int
}

struct DebugView: View {
    @State private var showingDelayPicker = false
    @State private var delaySeconds: String = "5"
    @State private var permissionStatus: String = "检查中..."
    @State private var lastResult: String?
    @State private var pendingNotifications: [PendingNotificationInfo] = []
    @State private var monitoredRegions: [MonitoredRegionInfo] = []

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

            Section {
                Button {
                    Task { await loadDebugInfo() }
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.blue)
                        Text("刷新触发器信息")
                    }
                }
            }

            Section("重置") {
                Button(role: .destructive) {
                    Task {
                        NotificationService.shared.cancelAllPendingNotifications()
                        await loadDebugInfo()
                        lastResult = "已清除所有时间提醒触发器"
                    }
                } label: {
                    HStack {
                        Image(systemName: "bell.slash")
                        Text("重置时间提醒触发器")
                    }
                }

                Button(role: .destructive) {
                    LocationService.shared.stopAllMonitoring()
                    Task {
                        await loadDebugInfo()
                        lastResult = "已停止所有地理围栏监控"
                    }
                } label: {
                    HStack {
                        Image(systemName: "location.slash")
                        Text("重置地理围栏配置")
                    }
                }
            }

            Section("待触发时间通知（\(pendingNotifications.count)）") {
                if pendingNotifications.isEmpty {
                    Text("暂无已调度的时间通知")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(pendingNotifications) { info in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(info.body)
                                .font(.subheadline)
                            HStack {
                                Text(formatDateComponents(info.dateComponents))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(info.repeats ? "重复" : "单次")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.1))
                                    .foregroundColor(.blue)
                                    .cornerRadius(4)
                            }
                            Text("ID: \(String(info.id.prefix(8)))…")
                                .font(.caption2)
                                .foregroundColor(Color(.tertiaryLabel))
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Section("地理围栏（\(monitoredRegions.count)）") {
                if monitoredRegions.isEmpty {
                    Text("暂无监控中的地理围栏")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(monitoredRegions) { info in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(info.counterName)
                                    .font(.subheadline)
                                Spacer()
                                Text(info.isPaired ? "配对模式" : "独立模式")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(info.isPaired ? Color.orange.opacity(0.1) : Color.green.opacity(0.1))
                                    .foregroundColor(info.isPaired ? .orange : .green)
                                    .cornerRadius(4)
                            }
                            Text(String(format: "%.5f, %.5f  半径 %.0fm", info.center.latitude, info.center.longitude, info.radius))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if info.isPaired && info.activeNotificationCount > 0 {
                                Text("当前活跃通知：\(info.activeNotificationCount) 条")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                            Text("ID: \(String(info.id.prefix(8)))…")
                                .font(.caption2)
                                .foregroundColor(Color(.tertiaryLabel))
                        }
                        .padding(.vertical, 2)
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
            await loadDebugInfo()
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

    private func loadDebugInfo() async {
        // 查询待触发的时间通知
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        pendingNotifications = requests.compactMap { request in
            guard let trigger = request.trigger as? UNCalendarNotificationTrigger else { return nil }
            return PendingNotificationInfo(
                id: request.identifier,
                body: request.content.body,
                dateComponents: trigger.dateComponents,
                repeats: trigger.repeats
            )
        }

        // 查询监控中的地理围栏
        let locationService = LocationService.shared
        let metadata = locationService.geofenceMetadata
        monitoredRegions = locationService.locationManager.monitoredRegions.compactMap { region in
            guard let circle = region as? CLCircularRegion else { return nil }
            let meta = metadata[circle.identifier]
            return MonitoredRegionInfo(
                id: circle.identifier,
                center: circle.center,
                radius: circle.radius,
                counterName: meta?.counterName ?? "未知",
                isPaired: meta?.isPaired ?? false,
                activeNotificationCount: meta?.activeNotificationIds.count ?? 0
            )
        }
    }

    private func formatDateComponents(_ dc: DateComponents) -> String {
        var parts: [String] = []
        if let weekday = dc.weekday {
            let names = ["", "周日", "周一", "周二", "周三", "周四", "周五", "周六"]
            parts.append(weekday < names.count ? names[weekday] : "周\(weekday)")
        }
        if let day = dc.day { parts.append("每月\(day)日") }
        if let hour = dc.hour, let minute = dc.minute {
            parts.append(String(format: "%02d:%02d", hour, minute))
        }
        return parts.joined(separator: " ")
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
