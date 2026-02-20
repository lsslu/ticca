//
//  HomeView.swift
//  ticca
//
//  Created by lss on 2025/11/16.
//

import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Counter.name) private var counters: [Counter]
    @State private var showCreateCounter = false
    @State private var showingDebug = false
    
    let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 背景色
                Color(red: 0.95, green: 0.95, blue: 0.97)
                    .ignoresSafeArea()
                
                VStack(alignment: .leading, spacing: 0) {
                    // 顶部标题区域
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("计数器")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundColor(.black)
                                .onTapGesture { showingDebug = true }
                            
                            Text("记录生活中的点滴累积")
                                .font(.system(size: 15))
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                        
                        // 创建按钮
                        Button(action: {
                            showCreateCounter = true
                        }) {
                            Image(systemName: "plus")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 52, height: 52)
                                .background(Color.black)
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                    
                    // 计数器网格
                    ScrollView {
                        if counters.isEmpty {
                            // 空状态
                            VStack(spacing: 16) {
                                Spacer()
                                    .frame(height: 80)
                                
                                Image(systemName: "square.stack.3d.up.slash")
                                    .font(.system(size: 48))
                                    .foregroundColor(.gray.opacity(0.5))
                                
                                Text("暂无计数器")
                                    .font(.system(size: 17))
                                    .foregroundColor(.gray)
                                
                                Text("点击右上角 + 创建一个")
                                    .font(.system(size: 14))
                                    .foregroundColor(.gray.opacity(0.7))
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(counters) { counter in
                                    CounterGridItem(counter: counter)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(isPresented: $showingDebug) {
                DebugView()
            }
            .sheet(isPresented: $showCreateCounter) {
                CreateCounterView()
            }
        }
    }
}

struct CounterGridItem: View {
    @Environment(\.modelContext) private var modelContext
    let counter: Counter
    
    var body: some View {
        NavigationLink(destination: CounterDetailView(counter: counter)) {
            VStack(alignment: .leading, spacing: 0) {
                // 图标
                Image(systemName: counter.icon.rawValue)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.black)
                    .clipShape(Circle())
                    .padding(.bottom, 16)
                
                // 计数数字
                Text("\(counter.getCurrentCount())")
                    .font(.system(size: 48, weight: .regular))
                    .foregroundColor(.black)
                    .padding(.bottom, 4)
                
                // 计数器名称
                Text(counter.name)
                    .font(.system(size: 15))
                    .foregroundColor(.gray)
                    .lineLimit(1)
                
                Spacer()
                    .frame(height: 16)
                
                // 计数按钮
                Button(action: {
                    addCount()
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.black)
                        .clipShape(Capsule())
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .cornerRadius(20)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func addCount() {
        if counter.canCount() {
            let log = CounterLog(Date())
            counter.logs.append(log)
        }
    }
}

#Preview {
    HomeView()
        .modelContainer(for: Counter.self, inMemory: true)
}
