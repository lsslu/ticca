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
    @State private var showingBackfill: Bool = false

    /// 是否有可补填的日期（昨天及之前在某个周期内）
    private var canBackfill: Bool {
        let calendar = Calendar.current
        let yesterday = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -1, to: Date())!)
        // 只要昨天不早于最早周期的起始日，就可以补填
        if let firstPeriod = periods.last { // periods 已经按最新在前排序，last 是最早的
            return yesterday >= calendar.startOfDay(for: firstPeriod.start)
        }
        // 没有历史周期时，检查当前周期
        let currentPeriod = counter.getCurrentPeriod()
        return yesterday >= calendar.startOfDay(for: currentPeriod.start)
    }

    var body: some View {
        List {
            if canBackfill {
                Button {
                    showingBackfill = true
                } label: {
                    BackfillEntryCard()
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

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
        .sheet(isPresented: $showingBackfill) {
            BackfillHistoryView(counter: counter)
        }
    }

    private func updatePeriods() {
        periods = counter.getAllPeriods().reversed() // 最新的在前面
    }
}

struct BackfillEntryCard: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(Color.blue)
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 2) {
                Text("补填历史记录")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                Text("补填截止到昨天为止的计次")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundColor(Color(UIColor.tertiaryLabel))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.white)
        .cornerRadius(12)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
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
