//
//  ContentView.swift
//  ticca
//
//  Created by lss on 2025/11/15.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [Item]

    var body: some View {
        GeometryReader { geometry in
            let safeAreaInsets = geometry.safeAreaInsets
            let totalHeight = geometry.size.height + safeAreaInsets.top + safeAreaInsets.bottom
            
            ZStack {
                Color.clear
                    .ignoresSafeArea()
                
                Button(action: {
                    
                }) {
                    Text("Create a counter")
                        .font(.default)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 60)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 60)
                                        .strokeBorder(
                                            LinearGradient(
                                                gradient: Gradient(colors: [
                                                    Color.white.opacity(0.6),
                                                    Color.white.opacity(0.1)
                                                ]),
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1
                                        )
                                )
                        )
                        .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
                }
                .frame(width: geometry.size.width - 40, height: totalHeight - 40)
                .position(x: geometry.size.width / 2, y: totalHeight / 2)
            }
        }
        .ignoresSafeArea()
    }

    private func addItem() {
        withAnimation {
            let newCounter = Counter(
                name: "加班",
                frequency: Frequency(unit: FrequencyUnit.monthly, maxCount: 1),
                period: Period.monthly
            )
            modelContext.insert(newCounter)
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(items[index])
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
