//
//  ReminderConfigView.swift
//  ticca
//

import SwiftUI

struct ReminderConfigView: View {
    @Binding var reminderConfig: ReminderConfig?

    @State private var showingTemplatePicker = false
    @State private var editingIndex: Int? = nil
    @State private var newTemplate: TriggerTemplate? = nil

    var body: some View {
        Section("提醒") {
            // 触发条件列表
            if let config = reminderConfig {
                ForEach(Array(config.triggerConditions.enumerated()), id: \.element.id) { index, cond in
                    Button {
                        editingIndex = index
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(cond.summary)
                                    .font(.system(size: 15))
                                    .foregroundColor(.primary)
                                if let badge = strategyBadge(cond) {
                                    Text(badge)
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.1))
                                        .foregroundColor(.blue)
                                        .cornerRadius(4)
                                }
                            }

                            Spacer()

                            Toggle("", isOn: Binding(
                                get: { cond.isEnabled },
                                set: { newValue in
                                    reminderConfig?.triggerConditions[index].isEnabled = newValue
                                }
                            ))
                            .labelsHidden()

                            Button {
                                deleteCondition(at: index)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                                    .font(.system(size: 14))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            // 添加按钮
            Button {
                showingTemplatePicker = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.blue)
                    Text("添加触发条件")
                        .foregroundColor(.blue)
                }
            }
        }
        .sheet(isPresented: $showingTemplatePicker) {
            TriggerTemplatePickerView { template in
                showingTemplatePicker = false
                newTemplate = template
            }
        }
        .sheet(item: $newTemplate) { template in
            TriggerConditionEditorView(template: template) { newCond in
                if reminderConfig == nil {
                    reminderConfig = ReminderConfig()
                }
                reminderConfig?.triggerConditions.append(newCond)
            }
        }
        .sheet(item: Binding(
            get: { editingIndex.flatMap { idx -> EditingIndex? in EditingIndex(value: idx) } },
            set: { editingIndex = $0?.value }
        )) { ei in
            if let cond = reminderConfig?.triggerConditions[safe: ei.value] {
                TriggerConditionEditorView(editing: cond) { updated in
                    if reminderConfig?.triggerConditions.indices.contains(ei.value) == true {
                        reminderConfig?.triggerConditions[ei.value] = updated
                    }
                }
            }
        }
    }

    private func deleteCondition(at index: Int) {
        reminderConfig?.triggerConditions.remove(at: index)
        if reminderConfig?.triggerConditions.isEmpty == true {
            reminderConfig = nil
        }
    }

    private func strategyBadge(_ cond: TriggerCondition) -> String? {
        switch cond.missPolicy {
        case .drop: return "错过即丢弃"
        case .deferToNextOccurrence: return "错过补到下一周期"
        case .fireOnLateEntry: return "迟到补提醒"
        }
    }
}

// MARK: - 模板选择 sheet

struct TriggerTemplatePickerView: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (TriggerTemplate) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(TriggerTemplate.allCases) { template in
                    Button {
                        onSelect(template)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(template.title)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.primary)
                            Text(template.subtitle)
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("选择模板")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 工具

private struct EditingIndex: Identifiable {
    let value: Int
    var id: Int { value }
}

extension TriggerTemplate {
    // Identifiable already via id: String { rawValue }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
