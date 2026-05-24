//
//  MigrationTests.swift
//  ticcaTests
//

import Testing
import Foundation
@testable import ticca

struct MigrationTests {

    // MARK: - Helpers

    /// 构造一份旧格式 ReminderConfig 的 plist 字典
    private func makeLegacyDict(
        timeReminders: [[String: Any]] = [],
        locationReminders: [[String: Any]] = [],
        triggerConditions: [[String: Any]] = []
    ) -> [String: Any] {
        return [
            "timeReminders": timeReminders,
            "locationReminders": locationReminders,
            "triggerConditions": triggerConditions
            // 注意：旧格式没有 "v" 字段
        ]
    }

    private func encodePlist(_ dict: [String: Any]) throws -> Data {
        return try PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0)
    }

    private func decode(_ data: Data) throws -> ReminderConfig {
        return try PropertyListDecoder().decode(ReminderConfig.self, from: data)
    }

    // MARK: - 测试 1：纯时间提醒迁移

    @Test func migrate_pureTime() async throws {
        let dict = makeLegacyDict(
            timeReminders: [[
                "hour": 9,
                "minute": 30,
                "frequency": "每天",
                "isEnabled": true
            ]],
            triggerConditions: [[
                "id": "legacy-1",
                "timeReminderIndex": 0
            ]]
        )
        let data = try encodePlist(dict)
        let cfg = try decode(data)

        #expect(cfg.v == 2)
        #expect(cfg.triggerConditions.count == 1)
        let tc = cfg.triggerConditions[0]
        #expect(tc.id == "legacy-1")
        #expect(tc.isEnabled == true)
        #expect(tc.frequency == .daily)
        #expect(tc.missPolicy == .deferToNextOccurrence)
        if case .instant(let dc, let before, let after) = tc.time {
            #expect(dc.hour == 9)
            #expect(dc.minute == 30)
            #expect(before == 0)
            #expect(after == 0)
        } else {
            Issue.record("expected .instant time constraint")
        }
        if case .none = tc.location {
            // expected
        } else {
            Issue.record("expected .none location constraint")
        }
    }

    // MARK: - 测试 2：纯位置提醒迁移

    @Test func migrate_pureLocation() async throws {
        let dict = makeLegacyDict(
            locationReminders: [[
                "latitude": 31.2304,
                "longitude": 121.4737,
                "radius": 500.0,
                "locationName": "公司",
                "isEnabled": true
            ]],
            triggerConditions: [[
                "id": "legacy-2",
                "locationReminderIndex": 0
            ]]
        )
        let data = try encodePlist(dict)
        let cfg = try decode(data)

        #expect(cfg.triggerConditions.count == 1)
        let tc = cfg.triggerConditions[0]
        #expect(tc.id == "legacy-2")
        #expect(tc.frequency == .daily)
        #expect(tc.missPolicy == .fireOnLateEntry)
        if case .none = tc.time {
            // expected
        } else {
            Issue.record("expected .none time constraint")
        }
        if case .inside(let lat, let lon, let r, let name) = tc.location {
            #expect(lat == 31.2304)
            #expect(lon == 121.4737)
            #expect(r == 500.0)
            #expect(name == "公司")
        } else {
            Issue.record("expected .inside location constraint")
        }
    }

    // MARK: - 测试 3：配对（时间+位置）迁移

    @Test func migrate_paired() async throws {
        let dict = makeLegacyDict(
            timeReminders: [[
                "hour": 18,
                "minute": 0,
                "frequency": "每周",
                "isEnabled": true
            ]],
            locationReminders: [[
                "latitude": 31.0,
                "longitude": 121.0,
                "radius": 1000.0,
                "isEnabled": true
            ]],
            triggerConditions: [[
                "id": "legacy-3",
                "timeReminderIndex": 0,
                "locationReminderIndex": 0
            ]]
        )
        let data = try encodePlist(dict)
        let cfg = try decode(data)

        #expect(cfg.triggerConditions.count == 1)
        let tc = cfg.triggerConditions[0]
        #expect(tc.id == "legacy-3")
        #expect(tc.combinator == .and)
        #expect(tc.frequency == .weekly)
        #expect(tc.missPolicy == .deferToNextOccurrence)
        if case .instant(let dc, _, _) = tc.time {
            #expect(dc.hour == 18)
            #expect(dc.minute == 0)
        } else {
            Issue.record("expected .instant time")
        }
        if case .inside = tc.location {
            // expected
        } else {
            Issue.record("expected .inside location")
        }
    }

    // MARK: - 测试 4：损坏数据 → 失败即重置

    @Test func migrate_corrupted_resetsToEmpty() async throws {
        // triggerConditions 是一个非数组值，迁移应该返回空配置
        let dict: [String: Any] = [
            "timeReminders": [[
                "hour": 9,
                "minute": 0,
                "frequency": "每天",
                "isEnabled": true
            ]],
            "locationReminders": [],
            "triggerConditions": "this is not an array"
        ]
        let data = try encodePlist(dict)
        let cfg = try decode(data)

        // 完全重置（包括素材库）
        #expect(cfg.triggerConditions.isEmpty)
        #expect(cfg.timeReminders.isEmpty)
        #expect(cfg.locationReminders.isEmpty)
    }

    // MARK: - 测试 5：新格式（v=2）直读

    @Test func decode_v2_directly() async throws {
        let cfg = ReminderConfig(
            triggerConditions: [
                TriggerCondition(
                    id: "new-1",
                    time: .instant(at: { var d = DateComponents(); d.hour = 8; d.minute = 0; return d }(), windowBefore: 900, windowAfter: 900),
                    location: .inside(latitude: 31.0, longitude: 121.0, radius: 300, locationName: "家"),
                    combinator: .and,
                    frequency: .daily,
                    missPolicy: .drop
                )
            ]
        )
        let data = try PropertyListEncoder().encode(cfg)
        let decoded = try PropertyListDecoder().decode(ReminderConfig.self, from: data)

        #expect(decoded.v == 2)
        #expect(decoded.triggerConditions.count == 1)
        #expect(decoded.triggerConditions[0].id == "new-1")
        #expect(decoded.triggerConditions[0].missPolicy == .drop)
    }

    // MARK: - 测试 6：无配置（首次启动）

    @Test func migrate_empty() async throws {
        let dict = makeLegacyDict()
        let data = try encodePlist(dict)
        let cfg = try decode(data)
        #expect(cfg.triggerConditions.isEmpty)
        #expect(cfg.v == 2)
    }

    // MARK: - 测试 7：旧 condition 引用不存在的 index → compactMap 跳过

    @Test func migrate_invalidIndex_skipped() async throws {
        let dict = makeLegacyDict(
            timeReminders: [],
            triggerConditions: [
                ["id": "legacy-x", "timeReminderIndex": 99]
            ]
        )
        let data = try encodePlist(dict)
        let cfg = try decode(data)
        // 两个索引都解不到，nil/nil 情况下 compactMap 跳过
        #expect(cfg.triggerConditions.isEmpty)
    }
}
