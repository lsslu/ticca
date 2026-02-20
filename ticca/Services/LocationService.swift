//
//  LocationService.swift
//  ticca
//

import CoreLocation
import UserNotifications
import SwiftUI
import Combine

@MainActor
class LocationService: NSObject, ObservableObject {
    static let shared = LocationService()

    let locationManager = CLLocationManager()
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var currentLocation: CLLocation?

    // 冷却期：同一区域1小时内不重复触发
    private var lastTriggerTimes: [String: Date] = [:]
    private let cooldownInterval: TimeInterval = 3600

    // 存储 regionId -> counterName 的映射，用于触发通知时显示计数器名称
    private var regionCounterNames: [String: String] = [:]

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorizationStatus = locationManager.authorizationStatus
    }

    func requestWhenInUseAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }

    func requestAlwaysAuthorization() {
        locationManager.requestAlwaysAuthorization()
    }

    /// 开始监控地理围栏，返回 regionId
    func monitorRegion(counterName: String, reminder: LocationReminder) -> String? {
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
        region.notifyOnExit = false

        regionCounterNames[regionId] = counterName
        locationManager.startMonitoring(for: region)
        return regionId
    }

    func stopMonitoring(regionId: String) {
        if let region = locationManager.monitoredRegions.first(where: { $0.identifier == regionId }) {
            locationManager.stopMonitoring(for: region)
        }
        regionCounterNames.removeValue(forKey: regionId)
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

    private func canTrigger(regionId: String) -> Bool {
        guard let lastTime = lastTriggerTimes[regionId] else { return true }
        return Date().timeIntervalSince(lastTime) > cooldownInterval
    }

    private func sendLocationNotification(for region: CLRegion) async {
        let counterName = regionCounterNames[region.identifier] ?? "计数器"
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
            guard canTrigger(regionId: region.identifier) else { return }
            lastTriggerTimes[region.identifier] = Date()
            await sendLocationNotification(for: region)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 静默处理定位错误
    }
}
