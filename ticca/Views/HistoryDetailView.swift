//
//  HistoryDetailView.swift
//  ticca
//
//  Created by lss on 2025/11/16.
//

import SwiftUI
import SwiftData
import Charts

struct HistoryDetailView: View {
    let counter: Counter
    let period: (start: Date, end: Date)
    @State private var showingChart = false
    
    var periodLogs: [CounterLog] {
        counter.getLogs(for: period)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // 计数器信息
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: counter.icon.rawValue)
                            .font(.title2)
                            .foregroundColor(.blue)
                        Text(counter.name)
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                    
                    Text(formatDateRange(start: period.start, end: period.end))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("计数: \(periodLogs.count)")
                        .font(.headline)
                        .foregroundColor(.blue)
                }
                .padding()
                
                // 切换视图按钮
                Picker("视图", selection: $showingChart) {
                    Text("列表").tag(false)
                    Text("图表").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                
                // 内容视图
                if showingChart {
                    chartView
                } else {
                    listView
                }
            }
        }
        .navigationTitle("历史详情")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private var listView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("计数清单")
                .font(.headline)
                .padding(.horizontal)
            
            if periodLogs.isEmpty {
                Text("暂无记录")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                ForEach(periodLogs, id: \.dateTime) { log in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(formatDateTime(log.dateTime))
                                .font(.body)
                            Text(formatTime(log.dateTime))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal)
                }
            }
        }
    }
    
    private var chartView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("计数趋势")
                .font(.headline)
                .padding(.horizontal)
            
            if periodLogs.isEmpty {
                Text("暂无数据")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                Chart {
                    ForEach(Array(periodLogs.enumerated()), id: \.offset) { index, log in
                        LineMark(
                            x: .value("日期", log.dateTime, unit: .day),
                            y: .value("计数", index + 1)
                        )
                        .foregroundStyle(.blue)
                        
                        PointMark(
                            x: .value("日期", log.dateTime, unit: .day),
                            y: .value("计数", index + 1)
                        )
                        .foregroundStyle(.blue)
                    }
                }
                .frame(height: 300)
                .padding()
            }
        }
    }
    
    private func formatDateRange(start: Date, end: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(formatter.string(from: start)) 至 \(formatter.string(from: end))"
    }
    
    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

#Preview {
    NavigationStack {
        HistoryDetailView(
            counter: Counter(
                name: "测试计数器",
                icon: .clock,
                settlementPeriod: SettlementPeriod(type: .month, count: 1, startDay: 1, endDay: 31, endMonthOffset: 0)
            ),
            period: (Date(), Date())
        )
    }
    .modelContainer(for: Counter.self, inMemory: true)
}
