//
//  HistoryListView.swift
//  ticca
//
//  Created by lss on 2025/11/16.
//

import SwiftUI
import SwiftData

struct HistoryListView: View {
    let counter: Counter
    @State private var periods: [(start: Date, end: Date)] = []
    
    var body: some View {
        List {
            ForEach(Array(periods.enumerated()), id: \.offset) { index, period in
                NavigationLink(destination: HistoryDetailView(counter: counter, period: period)) {
                    HistoryListItem(counter: counter, period: period)
                }
            }
        }
        .navigationTitle("历史记录")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            updatePeriods()
        }
    }
    
    private func updatePeriods() {
        periods = counter.getAllPeriods().reversed() // 最新的在前面
    }
}

struct HistoryListItem: View {
    let counter: Counter
    let period: (start: Date, end: Date)
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(formatDateRange(start: period.start, end: period.end))
                    .font(.headline)
                
                Text("计数: \(counter.getCount(for: period))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    private func formatDateRange(start: Date, end: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(formatter.string(from: start)) 至 \(formatter.string(from: end))"
    }
}

#Preview {
    NavigationStack {
        HistoryListView(counter: Counter(
            name: "测试计数器",
            icon: .clock,
            settlementPeriod: SettlementPeriod(type: .month, count: 1, startDay: 1, endDay: 31, endMonthOffset: 0)
        ))
    }
    .modelContainer(for: Counter.self, inMemory: true)
}
