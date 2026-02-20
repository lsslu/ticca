//
//  PermissionRequestView.swift
//  ticca
//

import SwiftUI
import CoreLocation
import Combine

struct PermissionRequestView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var notificationService = NotificationService.shared
    @StateObject private var locationService = LocationService.shared

    let needsNotification: Bool
    let needsLocation: Bool
    let onComplete: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                Image(systemName: "bell.badge")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)

                Text("需要权限")
                    .font(.system(size: 24, weight: .bold))

                VStack(spacing: 16) {
                    if needsNotification {
                        PermissionRow(
                            icon: "bell.fill",
                            title: "通知权限",
                            description: "用于在设定的时间提醒您记录计数",
                            isGranted: notificationService.authorizationStatus == .authorized
                        )
                    }

                    if needsLocation {
                        PermissionRow(
                            icon: "location.fill",
                            title: "位置权限",
                            description: "用于在您到达指定位置时提醒您",
                            isGranted: locationService.authorizationStatus == .authorizedWhenInUse ||
                                       locationService.authorizationStatus == .authorizedAlways
                        )
                    }
                }
                .padding(.horizontal)

                Spacer()

                Button {
                    Task {
                        await requestPermissions()
                    }
                } label: {
                    Text("授予权限")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.black)
                        .cornerRadius(12)
                }
                .padding(.horizontal)

                Button("稍后再说") {
                    dismiss()
                }
                .foregroundColor(.gray)
                .padding(.bottom, 16)
            }
            .navigationTitle("权限请求")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func requestPermissions() async {
        if needsNotification {
            _ = await notificationService.requestAuthorization()
        }
        if needsLocation {
            locationService.requestWhenInUseAuthorization()
            // 短暂等待位置权限处理
            try? await Task.sleep(nanoseconds: 500_000_000)
            locationService.requestAlwaysAuthorization()
        }

        try? await Task.sleep(nanoseconds: 1_000_000_000)
        onComplete()
        dismiss()
    }
}

struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.blue)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                    if isGranted {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 16))
                    }
                }
                Text(description)
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}
