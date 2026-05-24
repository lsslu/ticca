//
//  LocationService.swift
//  ticca
//

import CoreLocation
import UserNotifications
import SwiftUI
import Combine

/// 围栏标识前缀，用于从 region.identifier 反查 conditionId
private let regionPrefix = "tc_"

@MainActor
class LocationService: NSObject, ObservableObject {
    static let shared = LocationService()

    let locationManager = CLLocationManager()
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var currentLocation: CLLocation?

    /// 待响应的 requestState(for:) 调用，regionId -> continuation
    private var pendingStateRequests: [String: CheckedContinuation<CLRegionState, Never>] = [:]

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorizationStatus = locationManager.authorizationStatus
    }

    // MARK: - Authorization

    func requestWhenInUseAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }

    func requestAlwaysAuthorization() {
        locationManager.requestAlwaysAuthorization()
    }

    // MARK: - Region Monitoring

    /// 为指定 conditionId 注册地理围栏
    /// 返回围栏 identifier；超出配额、不可用或权限不足时返回 nil
    func monitorRegion(
        conditionId: String,
        latitude: Double,
        longitude: Double,
        radius: Double
    ) -> String? {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return nil }
        if locationManager.monitoredRegions.count >= 20 { return nil }

        let regionId = regionPrefix + conditionId
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let region = CLCircularRegion(
            center: coordinate,
            radius: max(radius, 100),
            identifier: regionId
        )
        region.notifyOnEntry = true
        region.notifyOnExit = false

        locationManager.startMonitoring(for: region)
        return regionId
    }

    func stopMonitoring(regionId: String) {
        if let region = locationManager.monitoredRegions.first(where: { $0.identifier == regionId }) {
            locationManager.stopMonitoring(for: region)
        }
    }

    func stopAllMonitoring() {
        for region in locationManager.monitoredRegions {
            locationManager.stopMonitoring(for: region)
        }
        for (_, cont) in pendingStateRequests {
            cont.resume(returning: .unknown)
        }
        pendingStateRequests.removeAll()
    }

    func requestCurrentLocation() {
        locationManager.requestLocation()
    }

    // MARK: - State Query

    /// 主动查询围栏状态，2 秒兜底超时返回 .unknown
    func currentState(for regionId: String) async -> CLRegionState {
        guard let region = locationManager.monitoredRegions.first(where: { $0.identifier == regionId }) else {
            return .unknown
        }
        return await withCheckedContinuation { (cont: CheckedContinuation<CLRegionState, Never>) in
            pendingStateRequests[regionId] = cont
            locationManager.requestState(for: region)
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let self = self else { return }
                if let pending = self.pendingStateRequests.removeValue(forKey: regionId) {
                    pending.resume(returning: .unknown)
                }
            }
        }
    }

    /// 解析 region.identifier 还原 conditionId
    static func conditionId(fromRegionId regionId: String) -> String? {
        guard regionId.hasPrefix(regionPrefix) else { return nil }
        return String(regionId.dropFirst(regionPrefix.count))
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
        let regionId = region.identifier
        Task { @MainActor in
            guard let conditionId = LocationService.conditionId(fromRegionId: regionId) else { return }
            await TriggerEvaluator.shared.handleRegionEntry(conditionId: conditionId)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        let regionId = region.identifier
        Task { @MainActor in
            if let pending = pendingStateRequests.removeValue(forKey: regionId) {
                pending.resume(returning: state)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 静默处理定位错误
    }
}
