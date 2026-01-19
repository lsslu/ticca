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
    
    let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    // 创建计数器入口
                    NavigationLink(destination: CreateCounterView()) {
                        VStack {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.blue)
                            Text("创建计数器")
                                .font(.headline)
                                .foregroundColor(.primary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 120)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .strokeBorder(Color.blue.opacity(0.3), lineWidth: 2)
                                )
                        )
                    }
                    
                    // 计数器列表
                    ForEach(counters) { counter in
                        NavigationLink(destination: CounterDetailView(counter: counter)) {
                            CounterGridItem(counter: counter)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("计数器")
        }
    }
}

struct CounterGridItem: View {
    let counter: Counter
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: counter.icon.rawValue)
                .font(.system(size: 32))
                .foregroundColor(.blue)
            
            Text(counter.name)
                .font(.headline)
                .foregroundColor(.primary)
                .lineLimit(1)
            
            Text("\(counter.getCurrentCount())")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.blue)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 120)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.gray.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

#Preview {
    HomeView()
        .modelContainer(for: Counter.self, inMemory: true)
}
