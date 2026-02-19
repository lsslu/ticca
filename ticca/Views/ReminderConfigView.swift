//
//  ReminderConfigView.swift
//  ticca
//

import SwiftUI

struct ReminderConfigView: View {
    @Binding var reminderConfig: ReminderConfig?
    var onAddTimeReminder: () -> Void
    var onAddLocationReminder: () -> Void

    var body: some View {
        Section("提醒设置") {
            // 时间提醒
            HStack {
                Label("时间提醒", systemImage: "clock")
                Spacer()
                Button {
                    onAddTimeReminder()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }

            if let config = reminderConfig {
                ForEach(Array(config.timeReminders.enumerated()), id: \.offset) { index, reminder in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(reminder.description)
                                .font(.system(size: 15))
                            Text(reminder.frequency.rawValue)
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Toggle("", isOn: Binding(
                            get: { reminder.isEnabled },
                            set: { newValue in
                                reminderConfig?.timeReminders[index].isEnabled = newValue
                            }
                        ))
                        .labelsHidden()

                        Button {
                            deleteTimeReminder(at: index)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                                .font(.system(size: 14))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 2)
                }
            }

            // 分隔
            Divider()

            // 位置提醒
            HStack {
                Label("位置提醒", systemImage: "location")
                Spacer()
                Button {
                    onAddLocationReminder()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }

            if let config = reminderConfig {
                ForEach(Array(config.locationReminders.enumerated()), id: \.offset) { index, reminder in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(reminder.locationName ?? "未命名位置")
                                .font(.system(size: 15))
                            Text("半径 \(Int(reminder.radius)) 米")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Toggle("", isOn: Binding(
                            get: { reminder.isEnabled },
                            set: { newValue in
                                reminderConfig?.locationReminders[index].isEnabled = newValue
                            }
                        ))
                        .labelsHidden()

                        Button {
                            deleteLocationReminder(at: index)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                                .font(.system(size: 14))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func deleteTimeReminder(at index: Int) {
        reminderConfig?.timeReminders.remove(at: index)
        cleanUpEmptyConfig()
    }

    private func deleteLocationReminder(at index: Int) {
        reminderConfig?.locationReminders.remove(at: index)
        cleanUpEmptyConfig()
    }

    private func cleanUpEmptyConfig() {
        if let config = reminderConfig,
           config.timeReminders.isEmpty && config.locationReminders.isEmpty {
            reminderConfig = nil
        }
    }
}
