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
        ZStack {
            // 背景色
            Color(red: 0.95, green: 0.95, blue: 0.97)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // 自定义导航栏
                HStack {
                    // 返回按钮
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.black)
                            .frame(width: 40, height: 40)
                            .background(Color.white)
                            .clipShape(Circle())
                    }

                    Text(counter.name)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.black)

                    Spacer()

                    // 更多按钮
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
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.black)
                            .frame(width: 40, height: 40)
                            .background(Color.white)
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 16)

                // 主内容卡片
                VStack(spacing: 24) {
                    // 图标
                    Image(systemName: counter.icon.rawValue)
                        .font(.system(size: 36, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 80, height: 80)
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 20))

                    // 当前周期标签
                    let (start, end) = counter.getCurrentPeriod()
                    VStack(spacing: 8) {
                        Text("当前周期")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(red: 0.95, green: 0.95, blue: 0.97))
                            .clipShape(Capsule())

                        Text(formatDateRange(start: start, end: end))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.black)
                    }

                    // 计数数字
                    Text("\(currentCount)")
                        .font(.system(size: 80, weight: .bold))
                        .foregroundColor(.black)

                    // 计数频次信息
                    if let freq = counter.frequency {
                        HStack(spacing: 4) {
                            if let remaining = remainingCount {
                                Text("剩余\(remaining)次")
                                    .font(.system(size: 14))
                                    .foregroundColor(remaining > 0 ? .gray : .red)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .background(Color.white)
                .cornerRadius(24)
                .padding(.horizontal, 20)

                Spacer()

                // 计数按钮
                Button(action: {
                    incrementCount()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .semibold))
                        Text(canCount ? "记一笔" : "已达上限")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 16)
                    .background(canCount ? Color.black : Color.gray)
                    .clipShape(Capsule())
                }
                .disabled(!canCount)
                .padding(.bottom, 40)
            }
        }
        .navigationBarHidden(true)
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
        formatter.dateFormat = "MM月dd日"
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
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
        icon: .star,
        settlementPeriod: SettlementPeriod(type: .month, count: 1, startDay: 1, endDay: 31, endMonthOffset: 0)
    )
    NavigationStack {
        CounterDetailView(counter: counter)
    }
    .modelContainer(for: Counter.self, inMemory: true)
}
