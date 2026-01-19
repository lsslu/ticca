//
//  Counter.swift
//  ticca
//
//  Created by lss on 2025/11/16.
//

import Foundation
import SwiftData

enum FrequencyUnit: String, Codable {
    case daily = "daily"
    case weekly = "weekly"
    case monthly = "monthly"
}

struct Frequency: Codable {
    var unit: FrequencyUnit
    var maxCount: Int
    
    var description: String {
        return "\(unit.rawValue) \(maxCount)"
    }
}

enum Period: String, Codable {
    case weekly = "weekly"
    case monthly = "monthly"
}

@Model
final class Counter {
    var name: String
    var frequency: Frequency?
    var period: Period?
    
    init(name: String, frequency: Frequency, period: Period) {
        self.name = name
        self.frequency = frequency
        self.period = period
    }
}

@Model
final class CounterLog {
    var dateTime: Date
    
    init(_ dateTime: Date) {
        self.dateTime = dateTime
    }
}
