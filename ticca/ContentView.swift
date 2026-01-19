//
//  ContentView.swift
//  ticca
//
//  Created by lss on 2025/11/15.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        HomeView()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Counter.self, inMemory: true)
}
