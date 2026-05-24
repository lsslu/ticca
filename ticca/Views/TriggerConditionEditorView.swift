//
//  TriggerConditionEditorView.swift
//  ticca
//
//  统一触发条件编辑页：时间 + 地点 + 组合策略 + 错过策略
//

import SwiftUI

enum TriggerTemplate: String, CaseIterable, Identifiable {
    case timeAtLocation = "A"   // 时间到 + 在地点（语义 A）
    case enterAndWait = "C"     // 进入地点等下一个时间（语义 C）
    case timeOrLocation = "OR"  // 时间到或进入地点
    case custom = "custom"      // 自定义

    var id: String { rawValue }

    var title: String {
        switch self {
        case .timeAtLocation: return "时间到 + 在地点"
        case .enterAndWait:   return "进入地点等下一个时间"
        case .timeOrLocation: return "时间到 或 进入地点"
        case .custom:         return "自定义"
        }
    }

    var subtitle: String {
        switch self {
        case .timeAtLocation: return "时间窗内进入地点才提醒，错过即丢弃"
        case .enterAndWait:   return "进入地点后，下一次 T 时刻提醒"
        case .timeOrLocation: return "时间到或人到地点，任一触发"
        case .custom:         return "完全手动配置"
        }
    }
}

struct TriggerConditionEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var includeTime: Bool
    @State private var includeLocation: Bool
    @State private var timeReminder: TimeReminder?
    @State private var locationReminder: LocationReminder?

    @State private var combinator: Combinator
    @State private var missPolicy: MissPolicy
    @State private var windowBeforeMinutes: Double
    @State private var windowAfterMinutes: Double
    @State private var hasExpiry: Bool
    @State private var expiresAt: Date

    @State private var showTimePicker = false
    @State private var showLocationPicker = false

    private let editingId: String?
    private let editingRuntime: (regionId: String?, pending: [String], lastFiredAt: Date?, consumedAt: Date?)?
    let onSave: (TriggerCondition) -> Void

    init(editing: TriggerCondition? = nil, template: TriggerTemplate = .timeAtLocation, onSave: @escaping (TriggerCondition) -> Void) {
        self.onSave = onSave
        if let e = editing {
            self.editingId = e.id
            self.editingRuntime = (e.regionId, e.pendingNotificationIds, e.lastFiredAt, e.consumedAt)
            _includeTime = State(initialValue: e.hasTimeConstraint)
            _includeLocation = State(initialValue: e.hasLocationConstraint)
            _combinator = State(initialValue: e.combinator)
            _missPolicy = State(initialValue: e.missPolicy)
            _windowBeforeMinutes = State(initialValue: e.timeWindowBefore / 60)
            _windowAfterMinutes = State(initialValue: e.timeWindowAfter / 60)
            _hasExpiry = State(initialValue: e.expiresAt != nil)
            _expiresAt = State(initialValue: e.expiresAt ?? Date().addingTimeInterval(24 * 3600))
            // 从 TimeConstraint 还原 TimeReminder
            if case .instant(let dc, _, _) = e.time {
                _timeReminder = State(initialValue: TimeReminder(
                    hour: dc.hour ?? 9,
                    minute: dc.minute ?? 0,
                    frequency: e.frequency,
                    isEnabled: true
                ))
            } else {
                _timeReminder = State(initialValue: nil)
            }
            // 从 LocationConstraint 还原 LocationReminder
            if case .inside(let lat, let lon, let r, let name) = e.location {
                _locationReminder = State(initialValue: LocationReminder(
                    latitude: lat, longitude: lon, radius: r,
                    locationName: name, isEnabled: true, regionId: nil
                ))
            } else {
                _locationReminder = State(initialValue: nil)
            }
        } else {
            self.editingId = nil
            self.editingRuntime = nil
            // 应用模板默认值
            switch template {
            case .timeAtLocation:
                _includeTime = State(initialValue: true)
                _includeLocation = State(initialValue: true)
                _combinator = State(initialValue: .and)
                _missPolicy = State(initialValue: .drop)
                _windowBeforeMinutes = State(initialValue: 15)
                _windowAfterMinutes = State(initialValue: 15)
            case .enterAndWait:
                _includeTime = State(initialValue: true)
                _includeLocation = State(initialValue: true)
                _combinator = State(initialValue: .and)
                _missPolicy = State(initialValue: .deferToNextOccurrence)
                _windowBeforeMinutes = State(initialValue: 0)
                _windowAfterMinutes = State(initialValue: 0)
            case .timeOrLocation:
                _includeTime = State(initialValue: true)
                _includeLocation = State(initialValue: true)
                _combinator = State(initialValue: .or)
                _missPolicy = State(initialValue: .fireOnLateEntry)
                _windowBeforeMinutes = State(initialValue: 0)
                _windowAfterMinutes = State(initialValue: 0)
            case .custom:
                _includeTime = State(initialValue: true)
                _includeLocation = State(initialValue: false)
                _combinator = State(initialValue: .and)
                _missPolicy = State(initialValue: .deferToNextOccurrence)
                _windowBeforeMinutes = State(initialValue: 0)
                _windowAfterMinutes = State(initialValue: 0)
            }
            _timeReminder = State(initialValue: nil)
            _locationReminder = State(initialValue: nil)
            _hasExpiry = State(initialValue: false)
            _expiresAt = State(initialValue: Date().addingTimeInterval(24 * 3600))
        }
    }

    private var isValid: Bool {
        let hasTime = includeTime && timeReminder != nil
        let hasLoc = includeLocation && locationReminder != nil
        return hasTime || hasLoc
    }

    private var currentFrequency: ReminderFrequency {
        timeReminder?.frequency ?? .daily
    }

    var body: some View {
        NavigationStack {
            Form {
                // 时间约束
                Section("时间约束") {
                    Toggle("启用时间约束", isOn: $includeTime)
                    if includeTime {
                        Button {
                            showTimePicker = true
                        } label: {
                            HStack {
                                Image(systemName: "clock")
                                    .foregroundColor(.blue)
                                if let t = timeReminder {
                                    Text(t.description)
                                        .foregroundColor(.primary)
                                } else {
                                    Text("选择时间")
                                        .foregroundColor(.blue)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                        }
                    }
                }

                // 地点约束
                Section("地点约束") {
                    Toggle("启用地点约束", isOn: $includeLocation)
                    if includeLocation {
                        Button {
                            showLocationPicker = true
                        } label: {
                            HStack {
                                Image(systemName: "location")
                                    .foregroundColor(.blue)
                                if let l = locationReminder {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(l.locationName ?? "未命名位置")
                                            .foregroundColor(.primary)
                                        Text("半径 \(Int(l.radius)) 米")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                } else {
                                    Text("选择位置")
                                        .foregroundColor(.blue)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                        }
                    }
                }

                // 高级设置
                Section {
                    DisclosureGroup("高级设置") {
                        if includeTime && includeLocation {
                            Picker("组合方式", selection: $combinator) {
                                Text("同时满足").tag(Combinator.and)
                                Text("任一满足").tag(Combinator.or)
                            }
                        }

                        Picker("错过策略", selection: $missPolicy) {
                            Text("丢弃").tag(MissPolicy.drop)
                            Text("延后到下一周期").tag(MissPolicy.deferToNextOccurrence)
                            Text("迟到补提醒").tag(MissPolicy.fireOnLateEntry)
                        }

                        if includeTime {
                            VStack(alignment: .leading) {
                                HStack {
                                    Text("提前进入也算")
                                    Spacer()
                                    Text("\(Int(windowBeforeMinutes)) 分钟")
                                        .foregroundColor(.secondary)
                                        .font(.system(.body, design: .monospaced))
                                }
                                Slider(value: $windowBeforeMinutes, in: 0...60, step: 1)
                            }

                            VStack(alignment: .leading) {
                                HStack {
                                    Text("迟到补提醒窗口")
                                    Spacer()
                                    Text("\(Int(windowAfterMinutes)) 分钟")
                                        .foregroundColor(.secondary)
                                        .font(.system(.body, design: .monospaced))
                                }
                                Slider(value: $windowAfterMinutes, in: 0...60, step: 1)
                            }
                        }

                        if currentFrequency == .once {
                            Toggle("设置过期时间", isOn: $hasExpiry)
                            if hasExpiry {
                                DatePicker("过期时间", selection: $expiresAt, displayedComponents: [.date, .hourAndMinute])
                            }
                        }
                    }
                }
            }
            .navigationTitle(editingId == nil ? "新建触发条件" : "编辑触发条件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") { save() }
                        .disabled(!isValid)
                }
            }
            .sheet(isPresented: $showTimePicker) {
                TimeReminderPickerView(editing: timeReminder) { tr in
                    timeReminder = tr
                }
            }
            .sheet(isPresented: $showLocationPicker) {
                LocationReminderPickerView(editing: locationReminder) { lr in
                    locationReminder = lr
                }
            }
        }
    }

    private func save() {
        // 构造 TimeConstraint
        let timeC: TimeConstraint
        if includeTime, let t = timeReminder {
            var dc = DateComponents()
            dc.hour = t.hour
            dc.minute = t.minute
            // weekly / monthly 用今天的 weekday / day 作为默认（与旧行为一致）
            if t.frequency == .weekly {
                dc.weekday = Calendar.current.component(.weekday, from: Date())
            }
            if t.frequency == .monthly {
                dc.day = Calendar.current.component(.day, from: Date())
            }
            timeC = .instant(
                at: dc,
                windowBefore: windowBeforeMinutes * 60,
                windowAfter: windowAfterMinutes * 60
            )
        } else {
            timeC = .none
        }

        // 构造 LocationConstraint
        let locC: LocationConstraint
        if includeLocation, let l = locationReminder {
            locC = .inside(
                latitude: l.latitude,
                longitude: l.longitude,
                radius: l.radius,
                locationName: l.locationName
            )
        } else {
            locC = .none
        }

        // 组合方式如果只有一个约束，强制 .and（OR 单约束等价于 AND 单约束）
        let effectiveCombinator: Combinator =
            (includeTime && includeLocation) ? combinator : .and

        var cond = TriggerCondition(
            id: editingId ?? UUID().uuidString,
            time: timeC,
            location: locC,
            combinator: effectiveCombinator,
            frequency: currentFrequency,
            missPolicy: missPolicy,
            isEnabled: true
        )
        if currentFrequency == .once && hasExpiry {
            cond.expiresAt = expiresAt
        }

        // 保留编辑模式下的运行时状态（除围栏 ID 和挂起通知 ID 外，setupReminders 会重新填）
        if let runtime = editingRuntime {
            cond.lastFiredAt = runtime.lastFiredAt
            cond.consumedAt = runtime.consumedAt
        }

        onSave(cond)
        dismiss()
    }
}
