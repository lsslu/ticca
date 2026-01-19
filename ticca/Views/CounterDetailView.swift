//
//  CounterDetailView.swift
//  ticca
//
//  Created by lss on 2025/11/16.
//

import SwiftUI
import SwiftData

struct CounterDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var counter: Counter
    @State private var currentCount: Int = 0
    @State private var totalCount: Int = 0
    @State private var canCount: Bool = true
    @State private var remainingCount: Int? = nil
    @State private var showingDeleteAlert: Bool = false
    @State private var showingEditSheet: Bool = false
    @State private var showingLimitAlert: Bool = false
    
    var body: some View {
        VStack(spacing: 24) {
            // 计数器信息
            VStack(spacing: 16) {
                Image(systemName: counter.icon.rawValue)
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                
                Text(counter.name)
                    .font(.title)
                    .fontWeight(.bold)
                
                Text(counter.settlementPeriod.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                // 计数频次信息
                if let freq = counter.frequency {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.badge.checkmark")
                            .foregroundColor(.orange)
                        Text(freq.description)
                            .font(.subheadline)
                            .foregroundColor(.orange)
                        if let remaining = remainingCount {
                            Text("(剩余\(remaining)次)")
                                .font(.caption)
                                .foregroundColor(remaining > 0 ? .green : .red)
                        }
                    }
                }
                
                // 当前周期信息
                let (start, end) = counter.getCurrentPeriod()
                VStack(spacing: 4) {
                    Text("当前周期")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formatDateRange(start: start, end: end))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            
            // 当前计数
            VStack(spacing: 8) {
                Text("\(currentCount)")
                    .font(.system(size: 72))
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
                
                Text("当期计数")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // 计数按钮
            Button(action: {
                incrementCount()
            }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text(canCount ? "计数" : "已达上限")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(canCount ? Color.blue : Color.gray)
                .cornerRadius(12)
            }
            .disabled(!canCount)
            .padding()
        }
        .padding()
        .navigationTitle(counter.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    NavigationLink(destination: HistoryListView(counter: counter)) {
                        Label("历史记录", systemImage: "clock.arrow.circlepath")
                    }
                    
                    Button {
                        showingEditSheet = true
                    } label: {
                        Label("编辑", systemImage: "pencil")
                    }
                    
                    Divider()
                    
                    Button(role: .destructive) {
                        showingDeleteAlert = true
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
            }
        }
        .alert("确认删除", isPresented: $showingDeleteAlert) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                deleteCounter()
            }
        } message: {
            Text("确定要删除计数器「\(counter.name)」吗？此操作不可撤销，所有计数记录将被删除。")
        }
        .sheet(isPresented: $showingEditSheet) {
            CreateCounterView(editingCounter: counter)
        }
        .alert("计数频次已达上限", isPresented: $showingLimitAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            if let freq = counter.frequency {
                Text("每\(freq.timeValue)\(freq.timeUnit.rawValue)最多\(freq.maxCount)次")
            }
        }
        .onAppear {
            updateCurrentCount()
        }
        .onChange(of: counter.logs.count) { oldValue, newValue in
            updateCurrentCount()
        }
    }
    
    private func deleteCounter() {
        modelContext.delete(counter)
        try? modelContext.save()
        dismiss()
    }
    
    private func updateCurrentCount() {
        currentCount = counter.getCurrentCount()
        totalCount = counter.logs.count
        canCount = counter.canCount()
        remainingCount = counter.getRemainingCount()
    }
    
    private func incrementCount() {
        guard counter.canCount() else {
            showingLimitAlert = true
            return
        }
        
        let log = CounterLog(Date())
        counter.logs.append(log)
        totalCount = counter.logs.count
        currentCount = counter.getCurrentCount()
        canCount = counter.canCount()
        remainingCount = counter.getRemainingCount()
    }
    
    private func formatDateRange(start: Date, end: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(formatter.string(from: start)) 至 \(formatter.string(from: end))"
    }
    
    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}

#Preview {
    let counter = Counter(
        name: "测试计数器",
        icon: .clock,
        settlementPeriod: SettlementPeriod(type: .month, count: 1, startDay: 1, endDay: 31, endMonthOffset: 0)
    )
    return NavigationStack {
        CounterDetailView(counter: counter)
    }
    .modelContainer(for: Counter.self, inMemory: true)
}
