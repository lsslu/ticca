//
//  TimeReminderPickerView.swift
//  ticca
//

import SwiftUI

struct TimeReminderPickerView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTime = Date()
    @State private var selectedFrequency: ReminderFrequency = .daily

    let onSave: (TimeReminder) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("提醒时间") {
                    DatePicker("时间", selection: $selectedTime, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                Section("提醒频率") {
                    Picker("频率", selection: $selectedFrequency) {
                        ForEach(ReminderFrequency.allCases, id: \.self) { freq in
                            Text(freq.rawValue).tag(freq)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("添加时间提醒")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        let calendar = Calendar.current
                        let components = calendar.dateComponents([.hour, .minute], from: selectedTime)
                        let reminder = TimeReminder(
                            hour: components.hour ?? 9,
                            minute: components.minute ?? 0,
                            frequency: selectedFrequency,
                            isEnabled: true,
                            notificationId: nil
                        )
                        onSave(reminder)
                        dismiss()
                    }
                }
            }
        }
    }
}
