# 触发条件统一模型设计

## 概述

当前 `TriggerCondition` 通过「时间提醒下标 + 位置提醒下标」表达触发关系，由 `recomputeTriggerConditions()` 自动做笛卡尔积，配对模式（时间+位置）依赖 `UNCalendarNotificationTrigger(repeats:true)` 在围栏内动态调度通知。

这套机制覆盖了「进入地点后等下一个时间」这一种语义（下称语义 C），但无法表达：

- 错过时间窗即丢弃（语义 A，例如"上班打卡"）
- 错过时间但还在地点内时补发（语义"迟到补提醒"）
- 时间区间（例如"工作时间内到家"）
- 单边时间约束（例如"3 点之后到达"）
- 任一条件满足即触发（OR 关系）

本设计将触发条件升级为统一模型：时间约束 + 位置约束 + 组合方式 + 错过策略，A/C 等具体语义降级为 UI 层的预设模板。

---

## 数据模型

### TimeConstraint

```swift
enum TimeConstraint: Codable, Hashable {
    case none
    case instant(at: DateComponents,
                 windowBefore: TimeInterval,
                 windowAfter: TimeInterval)
    case range(from: DateComponents, to: DateComponents)
}
```

- `DateComponents` 仅包含 `hour` / `minute` / 可选 `weekday` / `day`，绝对周期由 `TriggerCondition.frequency` 决定
- `instant` 的 `windowBefore` / `windowAfter` 均为非负秒数，0 表示精确时刻
- `range` 允许 `to < from` 表达跨日区间（如 22:00 - 02:00）

### LocationConstraint

```swift
enum LocationConstraint: Codable, Hashable {
    case none
    case inside(latitude: Double,
                longitude: Double,
                radius: CLLocationDistance,
                locationName: String?)
}
```

- `radius` 内部 clamp 到 `[100, 10_000]` 米
- `locationName` 仅用于 UI 显示

### Combinator

```swift
enum Combinator: String, Codable {
    case and
    case or
}
```

- `time == .none` 或 `location == .none` 时，`combinator` 不参与判定

### MissPolicy

```swift
enum MissPolicy: String, Codable {
    case drop                    // 语义 A：错过即丢弃
    case deferToNextOccurrence   // 语义 C：错过补到下一个周期
    case fireOnLateEntry         // 迟到补提醒：窗外进入立即补发
}
```

### TriggerCondition（重写）

```swift
struct TriggerCondition: Codable, Hashable {
    var id: String = UUID().uuidString
    var time: TimeConstraint
    var location: LocationConstraint
    var combinator: Combinator
    var frequency: ReminderFrequency        // daily / weekly / monthly / once
    var missPolicy: MissPolicy
    var isEnabled: Bool = true
    var expiresAt: Date?                    // once 频率下用于自动清理

    // 运行时状态（持久化但不参与配置语义）
    var pendingNotificationIds: [String] = []
    var regionId: String?
    var lastFiredAt: Date?

    var isValid: Bool {
        switch (time, location) {
        case (.none, .none): return false
        default: return true
        }
    }
}
```

### ReminderConfig（调整）

```swift
struct ReminderConfig: Codable, Hashable {
    var triggerConditions: [TriggerCondition]
    // timeReminders / locationReminders 可保留作为「最近用过」的素材库，
    // 但不再是真值源，也不再参与笛卡尔积推导
}
```

`recomputeTriggerConditions()` 删除。`triggerConditions` 由用户在 UI 上直接编辑。

---

## 旧数据迁移

遍历旧 `triggerConditions`，按下表映射：

| 旧条件 | 新条件 |
|---|---|
| 仅 `timeReminderIndex` | `time=.instant(±0)`, `location=.none`, `missPolicy=.deferToNextOccurrence`, `frequency=旧TimeReminder.frequency` |
| 仅 `locationReminderIndex` | `time=.none`, `location=.inside(..)`, `missPolicy=.fireOnLateEntry`, `frequency=.daily`（沿用旧"冷却 1 小时"语义近似） |
| 两者都有（配对） | `time=.instant(±0)`, `location=.inside(..)`, `combinator=.and`, `missPolicy=.deferToNextOccurrence`（语义 C） |

迁移函数在 `Counter.swift` 内提供：

```swift
extension ReminderConfig {
    static func migrate(legacy: LegacyReminderConfig) -> ReminderConfig { ... }
}
```

迁移时机：App 启动时检测 SwiftData 版本号，一次性升级所有 `Counter.reminderConfig`。

---

## 运行时仲裁

新增 `Services/TriggerEvaluator.swift` 作为唯一发通知的入口。

```swift
@MainActor
final class TriggerEvaluator {
    static let shared = TriggerEvaluator()

    enum Source {
        case timeTick(conditionId: String)
        case regionEntry(regionId: String)
        case reconcile
    }

    func evaluate(_ condition: TriggerCondition,
                  counterName: String,
                  source: Source) async
}
```

三个入口：

### 1. 时间 tick

`UNCalendarNotificationTrigger(repeats: false)` 在目标时间触发。在 `UNUserNotificationCenterDelegate.willPresent` 中：

- `combinator == .and` 且需要校验位置 → 拦截通知，调用 `evaluate`，由仲裁决定是否真正展示
- `combinator == .or` 或纯时间约束 → 直接展示

评估完成后必须立即调度下一次 tick（`repeats:false` 不会自动续期）。

### 2. 围栏进入

`LocationService.didEnterRegion` 拿到 `regionId` 后，反查所属 condition，调用 `evaluate`。

### 3. reconcile

App 启动 / 进入前台时遍历所有启用的 condition：

- 对围栏调 `requestState(for:)` 主动查状态
- 按 `missPolicy` 决定补发或刷新调度
- 清理已过期的 once 条件

### 仲裁真值表

| time 状态 | location 状态 | combinator | missPolicy | 行为 |
|---|---|---|---|---|
| satisfied | inside | and | * | 立即发送 |
| satisfied | outside | and | drop | 不发，等围栏进入也不补 |
| satisfied | outside | and | fireOnLateEntry | 不发，等围栏进入时补发 |
| satisfied | outside | and | deferToNextOccurrence | 不发，调度下一次 tick |
| missed | inside | and | drop | 不发 |
| missed | inside | and | fireOnLateEntry | 立即发送 |
| missed | inside | and | deferToNextOccurrence | 不发，调度下一次 tick |
| satisfied | * | or | * | 立即发送 |
| * | inside | or | * | 立即发送 |
| pending | * | * | * | 仅调度，不发送 |

「satisfied」= `instant` 落入 `[T-windowBefore, T+windowAfter]` 或 `range` 内的当前时刻；「missed」= 已超过 `T+windowAfter` 或 `range.to`；「pending」= 尚未到达 `T-windowBefore` 或 `range.from`。

### 去重

`lastFiredAt` 按 `frequency` 颗粒度判定：

- `daily` → `Calendar.isDate(_:inSameDayAs:)`
- `weekly` → `Calendar.isDate(_:equalTo:.weekOfYear)`
- `monthly` → `Calendar.isDate(_:equalTo:.month)`
- `once` → 触发后写 `consumedAt`，整体作废

---

## 服务层接入点

| 文件 | 改动 |
|---|---|
| `Models/Counter.swift:56-64` | 重写 `TriggerCondition`，删 `recomputeTriggerConditions`，加 migration |
| `Services/ReminderManager.swift:22-80` | `setupReminders` 不再做笛卡尔积，遍历 `triggerConditions` 调 `arm(_:)` |
| `Services/LocationService.swift:64` | 配对场景的 `UNCalendarNotificationTrigger` 改 `repeats:false`，`dateComponents` 显式 year/month/day |
| `Services/LocationService.swift:245` | `didEnterRegion` 改为只调 `TriggerEvaluator.evaluate(source: .regionEntry)` |
| `Services/NotificationService.swift:58-62` | weekly/monthly 修 bug，改为"下一个匹配日" |
| `Services/TriggerEvaluator.swift`（新增） | 仲裁中心，详见上节 |
| `ticcaApp.swift` | 启动时 `TriggerEvaluator.shared.reconcileAll()` |

地理围栏配额（iOS 限制 20 个）由 `ReminderManager` 统一记账：超出配额的 condition 保持 `isEnabled=true` 但 `regionId=nil`，UI 显示"未武装"提示。

---

## UI 预设

`ReminderConfigView` 顶部不直接暴露 `combinator` / `missPolicy`，而是提供三个模板按钮：

| 模板 | 等价配置 |
|---|---|
| **「时间到 + 在地点」**（语义 A） | `combinator=.and, missPolicy=.drop`, `windowBefore=windowAfter=15*60` |
| **「进入地点等下一个时间」**（语义 C） | `combinator=.and, missPolicy=.deferToNextOccurrence`, `windowBefore=windowAfter=0` |
| **「时间到 或 进入地点」** | `combinator=.or, missPolicy=.fireOnLateEntry` |

进阶用户在「高级」抽屉里可以：

- 调整 `windowBefore` / `windowAfter`
- 切换 `missPolicy`
- 把 `instant` 改为 `range`
- 启用 `expiresAt`（仅 once 频率）

---

## 风险点

### 1. willPresent 拦截的时间预算

iOS 后台被通知唤起后必须在 30 秒内完成判定。`TriggerEvaluator.checkLocation` 使用 `requestState(for:)` 是异步回调，需要：

- 设置 5 秒超时
- 超时后降级为「直接展示通知 + 文案标注可能未到达地点」
- 不允许阻塞 `willPresent` 的 completion handler

### 2. 围栏精度与延迟

- `radius < 100m` 时 iOS 围栏不可靠，硬性下限 100m
- `didEnterRegion` 可能延迟数分钟，需要靠 reconcile 兜底
- 半径越大延迟越小，但触发位置偏差越大；产品上建议默认 200~500m

### 3. 通知 ID 管理

每个 condition 可能同时持有：

- 一个围栏（`regionId`）
- 多个挂起的时间 tick 通知（`pendingNotificationIds`）

变更 / 删除 condition 时必须**一并**清理，否则会出现孤儿通知。`ReminderManager.cancelReminders(config:)` 需要遍历所有 condition 的两份 ID。

### 4. once 频率

- 新增 `expiresAt` 字段，过期由 reconcile 清理（取消围栏 + 取消挂起通知 + `isEnabled=false`）
- 触发后写 `consumedAt`，下次 reconcile 时一并清理
- UI 上 once 条件在已触发 / 已过期后默认折叠

---

## 阶段规划

### 第一阶段：模型与迁移

- 定义新 `TriggerCondition` / `TimeConstraint` / `LocationConstraint` 等类型
- 实现 `ReminderConfig.migrate(legacy:)` 与 SwiftData 版本号机制
- 单元测试覆盖迁移正确性

### 第二阶段：仲裁中心

- 新增 `TriggerEvaluator`，实现 `evaluate` / `reconcileAll`
- 改造 `LocationService.didEnterRegion` 走仲裁
- 改造 `NotificationService` 修 weekly/monthly bug，提供 `scheduleOneShot` API

### 第三阶段：UI 模板

- `ReminderConfigView` 加入三个预设模板
- 「高级」抽屉暴露完整字段
- DebugView 增加「模拟围栏进入」「模拟时间到达」两个仿真按钮

### 第四阶段：兜底与清理

- 围栏配额记账与 UI 提示
- once 频率过期清理
- 启动 reconcile 覆盖 App 被杀场景
