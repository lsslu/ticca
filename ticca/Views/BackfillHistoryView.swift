//
//  BackfillHistoryView.swift
//  ticca
//
//  Created by lss on 2026/3/19.
//

import SwiftUI
import SwiftData

struct BackfillHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let counter: Counter

    @State private var selectedDate: Date = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
    @State private var backfillCount: Int = 1

    private var yesterday: Date {
        Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date()))!
    }

    private var earliestDate: Date {
        if let earliestLog = counter.logs.min(by: { $0.dateTime < $1.dateTime }) {
            let periods = counter.getAllPeriods()
            if let firstPeriod = periods.first {
                return firstPeriod.start
            }
            return Calendar.current.startOfDay(for: earliestLog.dateTime)
        }
        return counter.getCurrentPeriod().start
    }

    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Info Banner
                HStack(spacing: 10) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 18))
                        .foregroundColor(.blue)
                    Text("仅可补填截止到昨天为止的计次记录")
                        .font(.system(size: 14))
                        .foregroundColor(.blue)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(red: 0.91, green: 0.94, blue: 1.0))
                .cornerRadius(12)

                // Date Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("选择日期")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                        .tracking(0.5)

                    HStack {
                        Image(systemName: "calendar")
                            .font(.system(size: 20))
                            .foregroundColor(.blue)

                        DatePicker(
                            "",
                            selection: $selectedDate,
                            in: earliestDate...yesterday,
                            displayedComponents: .date
                        )
                        .labelsHidden()

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.white)
                    .cornerRadius(12)
                }

                // Count Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("补填次数")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                        .tracking(0.5)

                    HStack {
                        Text("补填计次数量")
                            .font(.system(size: 17))
                            .foregroundColor(.primary)

                        Spacer()

                        // Stepper
                        HStack(spacing: 0) {
                            Button {
                                if backfillCount > 1 {
                                    backfillCount -= 1
                                }
                            } label: {
                                Image(systemName: "minus")
                                    .font(.system(size: 16))
                                    .foregroundColor(.primary)
                                    .frame(width: 36, height: 36)
                                    .background(Color(red: 0.95, green: 0.95, blue: 0.97))
                                    .cornerRadius(8)
                            }

                            Text("\(backfillCount)")
                                .font(.system(size: 20, weight: .semibold))
                                .frame(width: 48)
                                .multilineTextAlignment(.center)

                            Button {
                                backfillCount += 1
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 16))
                                    .foregroundColor(.white)
                                    .frame(width: 36, height: 36)
                                    .background(Color.blue)
                                    .cornerRadius(8)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.white)
                    .cornerRadius(12)
                }

                // Preview Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("补填记录预览")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                        .tracking(0.5)

                    VStack(spacing: 0) {
                        ForEach(1...backfillCount, id: \.self) { index in
                            if index > 1 {
                                Divider()
                                    .padding(.leading, 56)
                            }

                            HStack(spacing: 12) {
                                Text("\(index)")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 28, height: 28)
                                    .background(Color.blue)
                                    .clipShape(Circle())

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(dateFormatter.string(from: selectedDate))
                                        .font(.system(size: 15))
                                        .foregroundColor(.primary)
                                    Text("补填记录")
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                }

                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                    }
                    .background(Color.white)
                    .cornerRadius(12)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .background(Color(red: 0.95, green: 0.95, blue: 0.97).ignoresSafeArea())
            .navigationTitle("补填历史记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                    .foregroundColor(.blue)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        saveBackfill()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
                }
            }
        }
    }

    private func saveBackfill() {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: selectedDate)

        for i in 0..<backfillCount {
            // Spread logs across the day to give each a unique timestamp
            let secondsOffset = i * 60 // 1 minute apart
            let logDate = calendar.date(byAdding: .second, value: secondsOffset, to: dayStart)!
            let log = CounterLog(logDate)
            counter.logs.append(log)
        }

        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    BackfillHistoryView(counter: Counter(
        name: "测试计数器",
        icon: .clock,
        settlementPeriod: SettlementPeriod(type: .month, count: 1, startDay: 1, endDay: 31, endMonthOffset: 0)
    ))
    .modelContainer(for: Counter.self, inMemory: true)
}
