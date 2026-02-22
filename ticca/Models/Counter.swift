//
//  Counter.swift
//  ticca
//
//  Created by lss on 2025/11/16.
//

import Foundation
import SwiftData

enum PeriodType: String, Codable, CaseIterable {
    case day = "天"
    case month = "月"
    case year = "年"
}

enum FrequencyUnit: String, Codable, CaseIterable {
    case hour = "小时"
    case day = "天"
    case month = "月"
    case year = "年"
}

struct CountFrequency: Codable {
    var timeValue: Int      // 每多少时间单位
    var timeUnit: FrequencyUnit  // 时间单位
    var maxCount: Int       // 最多计数次数
    
    var description: String {
        return "每\(timeValue)\(timeUnit.rawValue)\(maxCount)次"
    }
}

// MARK: - Reminder Types

enum ReminderFrequency: String, Codable, CaseIterable {
    case daily = "每天"
    case weekly = "每周"
    case monthly = "每月"
}

struct TimeReminder: Codable, Hashable {
    var hour: Int
    var minute: Int
    var frequency: ReminderFrequency
    var isEnabled: Bool
    var notificationId: String?

    var description: String {
        let timeString = String(format: "%02d:%02d", hour, minute)
        return "\(frequency.rawValue) \(timeString)"
    }
}

struct LocationReminder: Codable, Hashable {
    var latitude: Double
    var longitude: Double
    var radius: Double = 1000
    var locationName: String?
    var isEnabled: Bool
    var regionId: String?

    var description: String {
        if let name = locationName {
            return "在「\(name)」附近"
        }
        return "位置提醒"
    }
}

struct ReminderConfig: Codable, Hashable {
    var timeReminders: [TimeReminder]
    var locationReminders: [LocationReminder]

    var hasAnyReminder: Bool {
        return timeReminders.contains(where: { $0.isEnabled }) ||
               locationReminders.contains(where: { $0.isEnabled })
    }
}

struct SettlementPeriod: Codable {
    var type: PeriodType
    var count: Int  // 多少天/月/年为一个周期
    var startDay: Int?  // 对于月/年：开始日期（日）
    var endDay: Int?    // 对于月/年：结束日期（日）
    var endMonthOffset: Int?  // 对于月：结束日期是当月(0)还是次月(1)
    
    var description: String {
        if type == .day {
            return "每\(count)天"
        } else if type == .month {
            if let startDay = startDay, let endDay = endDay, let endMonthOffset = endMonthOffset {
                let endMonthText = endMonthOffset == 0 ? "当月" : "次月"
                return "每\(count)个月（\(startDay)日 - \(endMonthText)\(endDay)日）"
            }
            return "每\(count)个月"
        } else if type == .year {
            if let startDay = startDay, let endDay = endDay {
                return "每\(count)年（\(startDay)日 - \(endDay)日）"
            }
            return "每\(count)年"
        }
        return ""
    }
}

enum CounterIcon: String, Codable, CaseIterable {
    case clock = "clock"
    case calendar = "calendar"
    case star = "star"
    case heart = "heart"
    case flame = "flame"
    case bolt = "bolt"
    case trophy = "trophy"
    case book = "book"
}

@Model
final class Counter {
    var name: String
    var icon: CounterIcon
    var settlementPeriod: SettlementPeriod
    var frequency: CountFrequency?  // 计数频次限制（可选）
    var reminderConfig: ReminderConfig?  // 提醒配置（可选）
    @Relationship(deleteRule: .cascade) var logs: [CounterLog] = []

    init(name: String, icon: CounterIcon, settlementPeriod: SettlementPeriod, frequency: CountFrequency? = nil, reminderConfig: ReminderConfig? = nil) {
        self.name = name
        self.icon = icon
        self.settlementPeriod = settlementPeriod
        self.frequency = frequency
        self.reminderConfig = reminderConfig
    }
    
    // 获取当前周期的开始和结束日期
    func getCurrentPeriod() -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date()
        
        switch settlementPeriod.type {
        case .day:
            // 对于天，从今天开始，持续count天
            let start = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .day, value: settlementPeriod.count - 1, to: start)!
            return (start, calendar.date(bySettingHour: 23, minute: 59, second: 59, of: end)!)
            
        case .month:
            // 对于月，需要根据startDay计算当前所在的周期
            let nowComponents = calendar.dateComponents([.year, .month, .day], from: now)
            let currentDay = nowComponents.day ?? 1
            let startDay = settlementPeriod.startDay ?? 1
            let endDay = settlementPeriod.endDay ?? 1
            
            var startComponents = DateComponents()
            startComponents.year = nowComponents.year
            startComponents.month = nowComponents.month
            startComponents.day = startDay
            
            // 如果当前日期小于开始日，说明当前周期从上个月开始
            if currentDay < startDay {
                startComponents.month = (startComponents.month ?? 1) - 1
            }
            
            var start = calendar.date(from: startComponents)!
            
            // 结束日期 = 开始日期 + periodCount 个月后的 endDay
            var endComponents = calendar.dateComponents([.year, .month], from: start)
            endComponents.month = (endComponents.month ?? 1) + settlementPeriod.count
            endComponents.day = endDay
            
            var end = calendar.date(from: endComponents)!
            let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: end)!
            
            return (start, endOfDay)
            
        case .year:
            // 对于年，类似月的逻辑
            let nowComponents = calendar.dateComponents([.year, .month, .day], from: now)
            let startDay = settlementPeriod.startDay ?? 1
            let endDay = settlementPeriod.endDay ?? 31
            
            var startComponents = DateComponents()
            startComponents.year = nowComponents.year
            startComponents.month = 1
            startComponents.day = startDay
            
            var start = calendar.date(from: startComponents)!
            
            // 如果当前日期在开始日期之前，回退到上一年
            if now < start {
                startComponents.year = (startComponents.year ?? 0) - 1
                start = calendar.date(from: startComponents)!
            }
            
            var endComponents = DateComponents()
            endComponents.year = (calendar.component(.year, from: start)) + settlementPeriod.count - 1
            endComponents.month = 12
            endComponents.day = endDay
            
            let end = calendar.date(from: endComponents)!
            let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: end)!
            
            return (start, endOfDay)
        }
    }
    
    // 获取当前周期的计数
    func getCurrentCount() -> Int {
        let (start, end) = getCurrentPeriod()
        return logs.filter { $0.dateTime >= start && $0.dateTime <= end }.count
    }
    
    // 获取当前频次周期内的计数
    func getFrequencyCount() -> Int {
        guard let freq = frequency else { return 0 }
        let calendar = Calendar.current
        let now = Date()
        
        var startDate: Date
        
        switch freq.timeUnit {
        case .hour:
            // 当前小时的开始
            let components = calendar.dateComponents([.year, .month, .day, .hour], from: now)
            startDate = calendar.date(from: components)!
            startDate = calendar.date(byAdding: .hour, value: -(freq.timeValue - 1), to: startDate)!
        case .day:
            // 当前天的开始
            startDate = calendar.startOfDay(for: now)
            startDate = calendar.date(byAdding: .day, value: -(freq.timeValue - 1), to: startDate)!
        case .month:
            // 当前月的开始
            let components = calendar.dateComponents([.year, .month], from: now)
            startDate = calendar.date(from: components)!
            startDate = calendar.date(byAdding: .month, value: -(freq.timeValue - 1), to: startDate)!
        case .year:
            // 当前年的开始
            let components = calendar.dateComponents([.year], from: now)
            startDate = calendar.date(from: components)!
            startDate = calendar.date(byAdding: .year, value: -(freq.timeValue - 1), to: startDate)!
        }
        
        return logs.filter { $0.dateTime >= startDate && $0.dateTime <= now }.count
    }
    
    // 检查是否可以计数（根据频次限制）
    func canCount() -> Bool {
        guard let freq = frequency else { return true }
        return getFrequencyCount() < freq.maxCount
    }
    
    // 获取剩余可计数次数
    func getRemainingCount() -> Int? {
        guard let freq = frequency else { return nil }
        return max(0, freq.maxCount - getFrequencyCount())
    }
    
    // 获取所有周期
    func getAllPeriods() -> [(start: Date, end: Date)] {
        var periods: [(start: Date, end: Date)] = []
        let calendar = Calendar.current
        
        // 找到最早的日志日期
        guard let earliestLog = logs.min(by: { $0.dateTime < $1.dateTime }) else {
            // 如果没有日志，返回当前周期
            periods.append(getCurrentPeriod())
            return periods
        }
        
        let earliestDate = earliestLog.dateTime
        let (currentStart, currentEnd) = getCurrentPeriod()
        
        // 从最早日期开始，生成所有周期
        var periodStart = earliestDate
        var periodEnd: Date
        
        switch settlementPeriod.type {
        case .day:
            periodStart = calendar.startOfDay(for: earliestDate)
            periodEnd = calendar.date(byAdding: .day, value: settlementPeriod.count - 1, to: periodStart)!
            periodEnd = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: periodEnd)!
            
            while periodStart <= currentEnd {
                periods.append((periodStart, periodEnd))
                periodStart = calendar.date(byAdding: .day, value: settlementPeriod.count, to: periodStart)!
                periodEnd = calendar.date(byAdding: .day, value: settlementPeriod.count - 1, to: periodStart)!
                periodEnd = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: periodEnd)!
            }
            
        case .month:
            let components = calendar.dateComponents([.year, .month], from: earliestDate)
            var startComponents = components
            startComponents.day = settlementPeriod.startDay ?? 1
            periodStart = calendar.date(from: startComponents)!

            while periodStart <= currentEnd {
                // 每次循环都基于 periodStart 重新计算 periodEnd
                var endComponents = calendar.dateComponents([.year, .month], from: periodStart)
                endComponents.month = (endComponents.month ?? 1) + settlementPeriod.count
                if let endMonthOffset = settlementPeriod.endMonthOffset, endMonthOffset > 0 {
                    endComponents.month = (endComponents.month ?? 1) + endMonthOffset - 1
                }
                endComponents.day = settlementPeriod.endDay ?? 1

                periodEnd = calendar.date(from: endComponents)!
                periodEnd = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: periodEnd)!

                periods.append((periodStart, periodEnd))

                // 移动到下一个周期的起始日期
                periodStart = calendar.date(byAdding: .month, value: settlementPeriod.count, to: periodStart)!
            }
            
        case .year:
            let components = calendar.dateComponents([.year], from: earliestDate)
            var startComponents = components
            startComponents.month = 1
            startComponents.day = settlementPeriod.startDay ?? 1
            periodStart = calendar.date(from: startComponents)!

            while periodStart <= currentEnd {
                // 每次循环都基于 periodStart 重新计算 periodEnd
                var endComponents = DateComponents()
                endComponents.year = calendar.component(.year, from: periodStart) + settlementPeriod.count - 1
                endComponents.month = 12
                endComponents.day = settlementPeriod.endDay ?? 31

                periodEnd = calendar.date(from: endComponents)!
                periodEnd = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: periodEnd)!

                periods.append((periodStart, periodEnd))

                // 移动到下一个周期的起始日期
                periodStart = calendar.date(byAdding: .year, value: settlementPeriod.count, to: periodStart)!
            }
        }
        
        return periods
    }
    
    // 获取指定周期的计数
    func getCount(for period: (start: Date, end: Date)) -> Int {
        return logs.filter { $0.dateTime >= period.start && $0.dateTime <= period.end }.count
    }
    
    // 获取指定周期的日志
    func getLogs(for period: (start: Date, end: Date)) -> [CounterLog] {
        return logs.filter { $0.dateTime >= period.start && $0.dateTime <= period.end }.sorted(by: { $0.dateTime < $1.dateTime })
    }
}

@Model
final class CounterLog {
    var dateTime: Date
    
    init(_ dateTime: Date) {
        self.dateTime = dateTime
    }
}
