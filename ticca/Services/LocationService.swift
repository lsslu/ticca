//
//  LocationService.swift
//  ticca
//

import CoreLocation
import UserNotifications
import SwiftUI
import Combine

// MARK: - Geofence Metadata Types

struct PairedTimeReminderInfo: Codable {
    var counterName: String
    var hour: Int
    var minute: Int
    var frequency: ReminderFrequency
}

struct GeofenceMetadata: Codable {
    var regionId: String
    var counterName: String
    var isPaired: Bool
    var pairedTimeReminders: [PairedTimeReminderInfo]
    var activeNotificationIds: [String]
}

// MARK: - LocationService

@MainActor
class LocationService: NSObject, ObservableObject {
    static let shared = LocationService()

    let locationManager = CLLocationManager()
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var currentLocation: CLLocation?

    // 冷却期：同一区域1小时内不重复触发（仅用于非配对的位置提醒）
    private var lastTriggerTimes: [String: Date] = [:]
    private let cooldownInterval: TimeInterval = 3600

    // 持久化的围栏元数据：regionId -> GeofenceMetadata
    private static let metadataKey = "GeofenceMetadataStore"
    private var metadataStore: [String: GeofenceMetadata] = [:] {
        didSet { persistMetadata() }
    }

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorizationStatus = locationManager.authorizationStatus
        loadMetadata()
    }

    // MARK: - Authorization

    func requestWhenInUseAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }

    func requestAlwaysAuthorization() {
        locationManager.requestAlwaysAuthorization()
    }

    // MARK: - Region Monitoring

    /// 开始监控地理围栏，返回 regionId
    /// - isPaired: 为 true 时表示配对模式，进入围栏时动态创建时间通知，离开时取消
    /// - pairedTimeReminders: 配对模式下，进入围栏时需要调度的时间提醒信息
    func monitorRegion(
        counterName: String,
        reminder: LocationReminder,
        isPaired: Bool = false,
        pairedTimeReminders: [PairedTimeReminderInfo] = []
    ) -> String? {
        guard reminder.isEnabled else { return nil }
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return nil }

        // iOS 限制最多 20 个地理围栏
        if locationManager.monitoredRegions.count >= 20 {
            return nil
        }

        let coordinate = CLLocationCoordinate2D(latitude: reminder.latitude, longitude: reminder.longitude)
        let regionId = UUID().uuidString
        let region = CLCircularRegion(center: coordinate, radius: reminder.radius, identifier: regionId)
        region.notifyOnEntry = true
        region.notifyOnExit = isPaired  // 配对模式需要监听离开事件以取消通知

        let metadata = GeofenceMetadata(
            regionId: regionId,
            counterName: counterName,
            isPaired: isPaired,
            pairedTimeReminders: pairedTimeReminders,
            activeNotificationIds: []
        )
        metadataStore[regionId] = metadata

        locationManager.startMonitoring(for: region)

        // 配对模式：检测用户是否已在围栏内，如果是则立即调度时间通知
        if isPaired {
            locationManager.requestState(for: region)
        }

        return regionId
    }

    func stopMonitoring(regionId: String) {
        // 先取消该围栏动态创建的时间通知
        cancelPairedTimeNotifications(for: regionId)

        if let region = locationManager.monitoredRegions.first(where: { $0.identifier == regionId }) {
            locationManager.stopMonitoring(for: region)
        }
        metadataStore.removeValue(forKey: regionId)
    }

    func stopAllMonitoring(for config: ReminderConfig?) {
        guard let config = config else { return }
        for reminder in config.locationReminders {
            if let regionId = reminder.regionId {
                stopMonitoring(regionId: regionId)
            }
        }
    }

    func requestCurrentLocation() {
        locationManager.requestLocation()
    }

    // MARK: - Dynamic Paired Notification Scheduling

    /// 进入配对围栏时，动态创建关联的时间通知
    private func schedulePairedTimeNotifications(for regionId: String) async {
        guard var metadata = metadataStore[regionId] else { return }

        // 防止重复调度：检查是否已有待触发的通知
        if !metadata.activeNotificationIds.isEmpty {
            let pendingRequests = await UNUserNotificationCenter.current().pendingNotificationRequests()
            let pendingIds = Set(pendingRequests.map { $0.identifier })
            let stillActive = metadata.activeNotificationIds.filter { pendingIds.contains($0) }
            if !stillActive.isEmpty {
                return
            }
            metadata.activeNotificationIds = []
        }

        var notificationIds: [String] = []
        for timeInfo in metadata.pairedTimeReminders {
            let timeReminder = TimeReminder(
                hour: timeInfo.hour,
                minute: timeInfo.minute,
                frequency: timeInfo.frequency,
                isEnabled: true
            )
            if let notifId = await NotificationService.shared.scheduleTimeReminder(
                counterName: metadata.counterName,
                reminder: timeReminder
            ) {
                notificationIds.append(notifId)
            }
        }

        metadata.activeNotificationIds = notificationIds
        metadataStore[regionId] = metadata
    }

    /// 离开配对围栏时，取消关联的时间通知
    private func cancelPairedTimeNotifications(for regionId: String) {
        guard var metadata = metadataStore[regionId] else { return }

        if !metadata.activeNotificationIds.isEmpty {
            UNUserNotificationCenter.current()
                .removePendingNotificationRequests(withIdentifiers: metadata.activeNotificationIds)
        }

        metadata.activeNotificationIds = []
        metadataStore[regionId] = metadata
    }

    // MARK: - Private Helpers

    private func canTrigger(regionId: String) -> Bool {
        guard let lastTime = lastTriggerTimes[regionId] else { return true }
        return Date().timeIntervalSince(lastTime) > cooldownInterval
    }

    private func sendLocationNotification(for region: CLRegion) async {
        let counterName = metadataStore[region.identifier]?.counterName ?? "计数器"
        let content = UNMutableNotificationContent()
        content.title = "位置提醒"
        content.body = "您已到达提醒位置，该为「\(counterName)」记一笔了"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Metadata Persistence

    private func persistMetadata() {
        if let data = try? JSONEncoder().encode(metadataStore) {
            UserDefaults.standard.set(data, forKey: Self.metadataKey)
        }
    }

    private func loadMetadata() {
        if let data = UserDefaults.standard.data(forKey: Self.metadataKey),
           let store = try? JSONDecoder().decode([String: GeofenceMetadata].self, from: data) {
            metadataStore = store
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            currentLocation = locations.last
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        Task { @MainActor in
            guard let metadata = metadataStore[region.identifier] else { return }

            if metadata.isPaired {
                // 配对模式：动态创建关联的时间通知
                await schedulePairedTimeNotifications(for: region.identifier)
            } else {
                // 非配对：直接发送位置通知（带冷却期）
                guard canTrigger(regionId: region.identifier) else { return }
                lastTriggerTimes[region.identifier] = Date()
                await sendLocationNotification(for: region)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        Task { @MainActor in
            guard let metadata = metadataStore[region.identifier], metadata.isPaired else { return }
            // 配对模式：离开围栏，取消关联的时间通知
            cancelPairedTimeNotifications(for: region.identifier)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        Task { @MainActor in
            guard let metadata = metadataStore[region.identifier], metadata.isPaired else { return }

            switch state {
            case .inside:
                // 用户已在围栏内（设置时/App 重启时检测到），补建时间通知
                if metadata.activeNotificationIds.isEmpty {
                    await schedulePairedTimeNotifications(for: region.identifier)
                }
            case .outside, .unknown:
                // 用户不在围栏内，确保没有残留通知
                if !metadata.activeNotificationIds.isEmpty {
                    cancelPairedTimeNotifications(for: region.identifier)
                }
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 静默处理定位错误
    }
}
