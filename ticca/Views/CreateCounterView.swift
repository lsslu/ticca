//
//  CreateCounterView.swift
//  ticca
//
//  Created by lss on 2025/11/16.
//

import SwiftUI
import SwiftData

struct CreateCounterView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    // 编辑模式：传入现有计数器
    var editingCounter: Counter?
    var isEditMode: Bool { editingCounter != nil }
    
    @State private var name: String = ""
    @State private var selectedIcon: CounterIcon = .clock
    @State private var periodType: PeriodType = .day
    @State private var periodCount: Int = 1
    @State private var startDay: Int = 1
    @State private var endDay: Int = 1
    
    // 计数频次
    @State private var enableFrequency: Bool = true
    @State private var frequencyTimeValue: Int = 1
    @State private var frequencyTimeUnit: FrequencyUnit = .day
    @State private var frequencyMaxCount: Int = 1
    
    let iconColumns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    init(editingCounter: Counter? = nil) {
        self.editingCounter = editingCounter
    }
    
    // 计算结束日期的前缀文本
    private var endDatePrefix: String {
        let unitText = periodType == .month ? "月" : "年"
        
        if periodCount == 1 {
            return "次\(unitText)"
        } else if periodCount == 2 {
            return "隔\(unitText)"
        } else {
            return "后\(periodCount)\(unitText)的"
        }
    }
    
    // 1-31日数组
    private let days = Array(1...31)
    
    var body: some View {
        NavigationStack {
            Form {
                Section("计数器名称") {
                    TextField("请输入计数器名称", text: $name)
                }
                
                Section("图标") {
                    LazyVGrid(columns: iconColumns, spacing: 16) {
                        ForEach(CounterIcon.allCases, id: \.self) { icon in
                            IconSelectionButton(
                                icon: icon,
                                isSelected: selectedIcon == icon,
                                action: {
                                    withAnimation {
                                        selectedIcon = icon
                                    }
                                }
                            )
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                Section("结算周期") {
                    // 周期数量和类型合并为一行
                    HStack(alignment: .center) {
                        Text("结算周期")
                        Spacer()
                        HStack(alignment: .center, spacing: 8) {
                            Stepper(value: $periodCount, in: 1...365) {
                                Text("\(periodCount)")
                                    .frame(minWidth: 30, alignment: .trailing)
                            }
                            Picker("", selection: $periodType) {
                                ForEach(PeriodType.allCases, id: \.self) { type in
                                    Text(type.rawValue).tag(type)
                                }
                            }
                            .pickerStyle(.menu)
                            .fixedSize()
                        }
                    }
                    
                    if periodType == .month || periodType == .year {
                        HStack {
                            Text("开始日期")
                            Spacer()
                            HStack(spacing: 4) {
                                Text("当\(periodType == .month ? "月" : "年")")
                                Picker("", selection: $startDay) {
                                    ForEach(days, id: \.self) { day in
                                        Text("\(day)").tag(day)
                                    }
                                }
                                .pickerStyle(.menu)
                                .fixedSize()
                                Text("日")
                            }
                        }
                        
                        HStack {
                            Text("结束日期")
                            Spacer()
                            HStack(spacing: 4) {
                                Text(endDatePrefix)
                                Picker("", selection: $endDay) {
                                    ForEach(days, id: \.self) { day in
                                        Text("\(day)").tag(day)
                                    }
                                }
                                .pickerStyle(.menu)
                                .fixedSize()
                                Text("日")
                            }
                        }
                    }
                }
                
                Section("计数频次") {
                    Toggle("启用频次限制", isOn: $enableFrequency)
                    
                    if enableFrequency {
                        // 第一行：每（）小时/天/月/年
                        HStack(alignment: .center) {
                            Text("每")
                            Stepper(value: $frequencyTimeValue, in: 1...365) {
                                Text("\(frequencyTimeValue)")
                                    .frame(minWidth: 30, alignment: .trailing)
                            }
                            Picker("", selection: $frequencyTimeUnit) {
                                ForEach(FrequencyUnit.allCases, id: \.self) { unit in
                                    Text(unit.rawValue).tag(unit)
                                }
                            }
                            .pickerStyle(.menu)
                            .fixedSize()
                        }
                        
                        // 第二行：最多（）次
                        HStack(alignment: .center) {
                            Text("最多")
                            Stepper(value: $frequencyMaxCount, in: 1...999) {
                                Text("\(frequencyMaxCount)")
                                    .frame(minWidth: 30, alignment: .trailing)
                            }
                            Text("次")
                        }
                    }
                }
            }
            .navigationTitle(isEditMode ? "编辑计数器" : "创建计数器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isEditMode ? "保存" : "创建") {
                        if isEditMode {
                            updateCounter()
                        } else {
                            createCounter()
                        }
                    }
                    .disabled(name.isEmpty)
                }
            }
            .onAppear {
                loadCounterData()
            }
        }
    }
    
    private func loadCounterData() {
        guard let counter = editingCounter else { return }
        name = counter.name
        selectedIcon = counter.icon
        periodType = counter.settlementPeriod.type
        periodCount = counter.settlementPeriod.count
        startDay = counter.settlementPeriod.startDay ?? 1
        endDay = counter.settlementPeriod.endDay ?? 1
        
        if let frequency = counter.frequency {
            enableFrequency = true
            frequencyTimeValue = frequency.timeValue
            frequencyTimeUnit = frequency.timeUnit
            frequencyMaxCount = frequency.maxCount
        } else {
            enableFrequency = false
        }
    }
    
    private func createCounter() {
        let settlementPeriod = SettlementPeriod(
            type: periodType,
            count: periodCount,
            startDay: (periodType == .month || periodType == .year) ? startDay : nil,
            endDay: (periodType == .month || periodType == .year) ? endDay : nil,
            endMonthOffset: periodCount > 0 ? periodCount - 1 : nil
        )
        
        var frequency: CountFrequency? = nil
        if enableFrequency {
            frequency = CountFrequency(
                timeValue: frequencyTimeValue,
                timeUnit: frequencyTimeUnit,
                maxCount: frequencyMaxCount
            )
        }
        
        let counter = Counter(
            name: name,
            icon: selectedIcon,
            settlementPeriod: settlementPeriod,
            frequency: frequency
        )
        
        modelContext.insert(counter)
        dismiss()
    }
    
    private func updateCounter() {
        guard let counter = editingCounter else { return }
        
        counter.name = name
        counter.icon = selectedIcon
        counter.settlementPeriod = SettlementPeriod(
            type: periodType,
            count: periodCount,
            startDay: (periodType == .month || periodType == .year) ? startDay : nil,
            endDay: (periodType == .month || periodType == .year) ? endDay : nil,
            endMonthOffset: periodCount > 0 ? periodCount - 1 : nil
        )
        
        if enableFrequency {
            counter.frequency = CountFrequency(
                timeValue: frequencyTimeValue,
                timeUnit: frequencyTimeUnit,
                maxCount: frequencyMaxCount
            )
        } else {
            counter.frequency = nil
        }
        
        try? modelContext.save()
        dismiss()
    }
}

struct IconSelectionButton: View {
    let icon: CounterIcon
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon.rawValue)
                .font(.system(size: 30))
                .foregroundColor(isSelected ? .blue : .gray)
                .frame(width: 60, height: 60)
                .background(
                    Circle()
                        .fill(isSelected ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
                )
                .overlay(
                    Circle()
                        .strokeBorder(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    CreateCounterView()
        .modelContainer(for: Counter.self, inMemory: true)
}
