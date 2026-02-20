//
//  LocationReminderPickerView.swift
//  ticca
//

import SwiftUI
import MapKit
import Combine

@MainActor
private class LocationSearchService: NSObject, ObservableObject {
    @Published var completions: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.resultTypes = [.address, .pointOfInterest]
        completer.delegate = self
    }

    func updateSearch(_ text: String) {
        if text.isEmpty {
            completions = []
        } else {
            completer.queryFragment = text
        }
    }
}

extension LocationSearchService: MKLocalSearchCompleterDelegate {
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        Task { @MainActor in
            self.completions = completer.results
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        // 静默处理搜索错误
    }
}

struct LocationReminderPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var locationService = LocationService.shared
    @StateObject private var searchService = LocationSearchService()

    @State private var locationName: String = ""
    @State private var searchText: String = ""
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var showPermissionDenied: Bool = false

    let onSave: (LocationReminder) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 地图
                Map(position: $cameraPosition) {
                    if let coordinate = selectedCoordinate {
                        Annotation("", coordinate: coordinate) {
                            ZStack {
                                Circle()
                                    .fill(.blue.opacity(0.15))
                                    .frame(width: 60, height: 60)
                                Circle()
                                    .fill(.blue)
                                    .frame(width: 14, height: 14)
                                Circle()
                                    .stroke(.white, lineWidth: 3)
                                    .frame(width: 14, height: 14)
                            }
                        }

                        MapCircle(center: coordinate, radius: 1000)
                            .foregroundStyle(.blue.opacity(0.1))
                            .stroke(.blue.opacity(0.5), lineWidth: 1)
                    }
                }
                .frame(height: 320)

                // 配置表单
                Form {
                    Section("搜索地址") {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                            TextField("搜索地址或地点", text: $searchText)
                                .autocorrectionDisabled()
                        }
                        .onChange(of: searchText) { _, newValue in
                            searchService.updateSearch(newValue)
                        }

                        ForEach(searchService.completions, id: \.self) { completion in
                            Button {
                                selectSearchResult(completion)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(completion.title)
                                        .font(.system(size: 15))
                                        .foregroundColor(.primary)
                                    if !completion.subtitle.isEmpty {
                                        Text(completion.subtitle)
                                            .font(.system(size: 13))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    Section("位置名称") {
                        TextField("输入位置名称（可选）", text: $locationName)
                    }

                    Section {
                        HStack {
                            Text("提醒半径")
                            Spacer()
                            Text("1000 米")
                                .foregroundColor(.secondary)
                        }
                    }

                    Section {
                        if let coord = selectedCoordinate {
                            HStack {
                                Image(systemName: "mappin.circle.fill")
                                    .foregroundColor(.blue)
                                Text(String(format: "%.4f, %.4f", coord.latitude, coord.longitude))
                                    .font(.system(size: 14, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }

                        Button {
                            useCurrentLocation()
                        } label: {
                            HStack {
                                Image(systemName: "location.fill")
                                Text("使用当前位置")
                            }
                        }
                    }
                }
            }
            .navigationTitle("添加位置提醒")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        guard let coordinate = selectedCoordinate else { return }
                        let reminder = LocationReminder(
                            latitude: coordinate.latitude,
                            longitude: coordinate.longitude,
                            radius: 1000,
                            locationName: locationName.isEmpty ? nil : locationName,
                            isEnabled: true,
                            regionId: nil
                        )
                        onSave(reminder)
                        dismiss()
                    }
                    .disabled(selectedCoordinate == nil)
                }
            }
            .onAppear {
                switch locationService.authorizationStatus {
                case .notDetermined:
                    locationService.requestWhenInUseAuthorization()
                case .denied, .restricted:
                    showPermissionDenied = true
                default:
                    break
                }
                if let coordinate = selectedCoordinate {
                    cameraPosition = .camera(
                        MapCamera(centerCoordinate: coordinate, distance: 12000)
                    )
                } else {
                    cameraPosition = .userLocation(fallback: .automatic)
                    locationService.requestCurrentLocation()
                }
            }
            .onChange(of: locationService.authorizationStatus) { _, newStatus in
                if newStatus == .denied || newStatus == .restricted {
                    showPermissionDenied = true
                }
            }
            .alert("需要位置权限", isPresented: $showPermissionDenied) {
                Button("前往设置") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                    dismiss()
                }
                Button("取消", role: .cancel) {
                    dismiss()
                }
            } message: {
                Text("位置提醒需要定位权限才能正常工作，请在系统设置中开启定位服务。")
            }
        }
    }

    private func selectSearchResult(_ completion: MKLocalSearchCompletion) {
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)
        search.start { response, _ in
            guard let item = response?.mapItems.first else { return }
            DispatchQueue.main.async {
                selectedCoordinate = item.placemark.coordinate
                locationName = completion.title
                cameraPosition = .camera(
                    MapCamera(centerCoordinate: item.placemark.coordinate, distance: 12000)
                )
                searchText = ""
                searchService.completions = []
            }
        }
    }

    private func useCurrentLocation() {
        locationService.requestCurrentLocation()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if let location = locationService.currentLocation {
                selectedCoordinate = location.coordinate
                cameraPosition = .camera(
                    MapCamera(centerCoordinate: location.coordinate, distance: 12000)
                )
            }
        }
    }
}
