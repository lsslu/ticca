//
//  TriggerEvaluatorTests.swift
//  ticcaTests
//

import Testing
import Foundation
@testable import ticca

struct TriggerEvaluatorTests {

    // MARK: - shouldFire 真值表

    @Test func and_satisfied_inside_fires() {
        #expect(TriggerEvaluator.shouldFire(time: .satisfied, location: .inside, combinator: .and, missPolicy: .drop))
        #expect(TriggerEvaluator.shouldFire(time: .satisfied, location: .inside, combinator: .and, missPolicy: .deferToNextOccurrence))
        #expect(TriggerEvaluator.shouldFire(time: .satisfied, location: .inside, combinator: .and, missPolicy: .fireOnLateEntry))
    }

    @Test func and_satisfied_outside_suppressed() {
        #expect(!TriggerEvaluator.shouldFire(time: .satisfied, location: .outside, combinator: .and, missPolicy: .drop))
        #expect(!TriggerEvaluator.shouldFire(time: .satisfied, location: .outside, combinator: .and, missPolicy: .fireOnLateEntry))
        #expect(!TriggerEvaluator.shouldFire(time: .satisfied, location: .outside, combinator: .and, missPolicy: .deferToNextOccurrence))
    }

    @Test func and_missed_inside_dropPolicy_suppressed() {
        #expect(!TriggerEvaluator.shouldFire(time: .missed, location: .inside, combinator: .and, missPolicy: .drop))
    }

    @Test func and_missed_inside_lateEntryPolicy_fires() {
        #expect(TriggerEvaluator.shouldFire(time: .missed, location: .inside, combinator: .and, missPolicy: .fireOnLateEntry))
    }

    @Test func and_missed_inside_deferPolicy_suppressed() {
        #expect(!TriggerEvaluator.shouldFire(time: .missed, location: .inside, combinator: .and, missPolicy: .deferToNextOccurrence))
    }

    @Test func and_pending_anything_suppressed() {
        let future = Date().addingTimeInterval(3600)
        #expect(!TriggerEvaluator.shouldFire(time: .pending(at: future), location: .inside, combinator: .and, missPolicy: .drop))
        #expect(!TriggerEvaluator.shouldFire(time: .pending(at: future), location: .outside, combinator: .and, missPolicy: .fireOnLateEntry))
    }

    @Test func or_satisfied_fires() {
        #expect(TriggerEvaluator.shouldFire(time: .satisfied, location: .outside, combinator: .or, missPolicy: .drop))
        #expect(TriggerEvaluator.shouldFire(time: .satisfied, location: .unknown, combinator: .or, missPolicy: .drop))
    }

    @Test func or_inside_fires() {
        let future = Date().addingTimeInterval(3600)
        #expect(TriggerEvaluator.shouldFire(time: .pending(at: future), location: .inside, combinator: .or, missPolicy: .drop))
        #expect(TriggerEvaluator.shouldFire(time: .missed, location: .inside, combinator: .or, missPolicy: .drop))
    }

    @Test func or_neither_suppressed() {
        let future = Date().addingTimeInterval(3600)
        #expect(!TriggerEvaluator.shouldFire(time: .pending(at: future), location: .outside, combinator: .or, missPolicy: .drop))
        #expect(!TriggerEvaluator.shouldFire(time: .missed, location: .outside, combinator: .or, missPolicy: .drop))
    }

    @Test func unknownLocation_treatedAsNotInside() {
        // unknown 既不是 inside 也不是 outside，AND 模式下应该和 outside 一样不触发
        #expect(!TriggerEvaluator.shouldFire(time: .satisfied, location: .unknown, combinator: .and, missPolicy: .drop))
        // OR 模式下，time satisfied 仍触发
        #expect(TriggerEvaluator.shouldFire(time: .satisfied, location: .unknown, combinator: .or, missPolicy: .drop))
    }

    // MARK: - timeStatus 边界

    @Test func timeStatus_none_alwaysSatisfied() {
        let s = TriggerEvaluator.timeStatus(.none, frequency: .daily, now: Date())
        #expect(s == .satisfied)
    }

    @Test func timeStatus_instant_withinWindow_satisfied() {
        // 构造一个"刚到点"的 instant：取当前 hh:mm，windowAfter = 60 秒
        let now = Date()
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: now)
        var dc = DateComponents()
        dc.hour = comps.hour
        dc.minute = comps.minute
        let time = TimeConstraint.instant(at: dc, windowBefore: 60, windowAfter: 60)
        let s = TriggerEvaluator.timeStatus(time, frequency: .daily, now: now)
        #expect(s == .satisfied)
    }

    @Test func timeStatus_instant_farFromAny_pending() {
        // 构造一个"和当前时间错开 6 小时"的 instant，windowBefore = 60 秒
        let now = Date()
        let cal = Calendar.current
        let target = cal.date(byAdding: .hour, value: 6, to: now)!
        let comps = cal.dateComponents([.hour, .minute], from: target)
        var dc = DateComponents()
        dc.hour = comps.hour
        dc.minute = comps.minute
        let time = TimeConstraint.instant(at: dc, windowBefore: 60, windowAfter: 60)
        let s = TriggerEvaluator.timeStatus(time, frequency: .daily, now: now)
        if case .pending = s {
            // expected
        } else {
            Issue.record("expected pending, got \(s)")
        }
    }

    // MARK: - nextFireTime

    @Test func nextFireTime_daily_returnsFutureMoment() {
        var dc = DateComponents()
        dc.hour = 9
        dc.minute = 0
        let cond = TriggerCondition(
            time: .instant(at: dc, windowBefore: 0, windowAfter: 0),
            location: .none,
            combinator: .and,
            frequency: .daily,
            missPolicy: .deferToNextOccurrence
        )
        let now = Date()
        let next = TriggerEvaluator.nextFireTime(for: cond, after: now)
        #expect(next != nil)
        #expect(next! > now)
    }

    @Test func nextFireTime_withWindowBefore_offsetsBack() {
        var dc = DateComponents()
        dc.hour = 9
        dc.minute = 0
        let condWindowed = TriggerCondition(
            time: .instant(at: dc, windowBefore: 900, windowAfter: 0),
            location: .none,
            combinator: .and,
            frequency: .daily,
            missPolicy: .drop
        )
        let condTight = TriggerCondition(
            time: .instant(at: dc, windowBefore: 0, windowAfter: 0),
            location: .none,
            combinator: .and,
            frequency: .daily,
            missPolicy: .drop
        )
        let now = Date()
        let nextWindowed = TriggerEvaluator.nextFireTime(for: condWindowed, after: now)!
        let nextTight = TriggerEvaluator.nextFireTime(for: condTight, after: now)!
        // 窗口版应该比精确版早 15 分钟
        #expect(abs(nextTight.timeIntervalSince(nextWindowed) - 900) < 1)
    }

    @Test func nextFireTime_none_returnsNil() {
        let cond = TriggerCondition(
            time: .none,
            location: .inside(latitude: 0, longitude: 0, radius: 200, locationName: nil),
            combinator: .and,
            frequency: .daily,
            missPolicy: .fireOnLateEntry
        )
        let next = TriggerEvaluator.nextFireTime(for: cond, after: Date())
        #expect(next == nil)
    }

    // MARK: - 辅助属性

    @Test func helperProperties() {
        var dc = DateComponents()
        dc.hour = 9
        dc.minute = 0
        let cond = TriggerCondition(
            time: .instant(at: dc, windowBefore: 900, windowAfter: 1800),
            location: .inside(latitude: 0, longitude: 0, radius: 200, locationName: nil),
            combinator: .and,
            frequency: .daily,
            missPolicy: .drop
        )
        #expect(cond.hasTimeConstraint)
        #expect(cond.hasLocationConstraint)
        #expect(cond.timeWindowBefore == 900)
        #expect(cond.timeWindowAfter == 1800)
        #expect(cond.needsLocationCheck == true)

        let pureTime = TriggerCondition(
            time: .instant(at: dc, windowBefore: 0, windowAfter: 0),
            location: .none,
            combinator: .and,
            frequency: .daily,
            missPolicy: .drop
        )
        #expect(pureTime.needsLocationCheck == false)

        let orCond = TriggerCondition(
            time: .instant(at: dc, windowBefore: 0, windowAfter: 0),
            location: .inside(latitude: 0, longitude: 0, radius: 200, locationName: nil),
            combinator: .or,
            frequency: .daily,
            missPolicy: .drop
        )
        // or 模式下时间到独立触发，不需要 willPresent 拦截做仲裁
        #expect(orCond.needsLocationCheck == false)
    }
}
