# Subly

> 一款安静、本地优先的 iPhone 订阅管理工具。

[![Swift](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)](https://swift.org)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-iOS%2018-0A84FF?logo=apple&logoColor=white)](https://developer.apple.com/xcode/swiftui/)
[![Storage](https://img.shields.io/badge/Storage-SwiftData-34C759?logo=icloud&logoColor=white)](https://developer.apple.com/xcode/swiftdata/)
[![Status](https://img.shields.io/badge/Status-v1.0.0-informational)](#)

[English](README.md) · **简体中文**

Subly 用来把每一笔订阅、试用、续费和一次性购买都放到眼前。它可以记录账单周期、下次扣费日、支付币种、提醒、分类支出和备份数据，让那些“悄悄续费”的服务变得清清楚楚。

它不是厚重的个人财务系统，而是一个轻量、快速、专注的订阅账本。

## 功能亮点

- **订阅账本**：支持活跃、暂停、取消、试用、一次性、过期、待决定续费等状态。
- **灵活账单周期**：支持周付、月付、季付、半年付、年付、自定义天数、一次性和试用期。
- **续费提醒**：可配置全局默认提醒，也能为订阅记录生成提醒计划。
- **多币种金额**：支持 CNY、USD、HKD、JPY、EUR、GBP，并支持 CNY / USD 作为主要展示货币。
- **支出统计**：分类占比、服务排行、月度趋势、年度趋势，基于 Swift Charts 展示。
- **分类与模板**：内置种子数据，并支持分类管理，让订阅记录保持整洁。
- **备份与恢复**：支持 JSON 导出 / 导入，提供合并恢复和覆盖恢复。
- **本地优先架构**：使用 SwiftUI + SwiftData，核心领域、仓储、服务和视图模型都有测试覆盖。

## 页面结构

Subly 由三个主要标签页组成：

- **订阅**：总览、活跃 / 历史筛选、即将到期、订阅详情。
- **统计**：分类支出、服务排行、月度趋势、年度趋势。
- **设置**：显示货币、外观、提醒、分类、备份与恢复。

## 技术栈

- **语言**：Swift 6
- **界面**：SwiftUI
- **数据持久化**：SwiftData
- **图表**：Swift Charts
- **通知**：UserNotifications
- **平台目标**：iOS 18+
- **项目格式**：Xcode project (`Subly.xcodeproj`)

## 快速开始

环境要求：

- 安装 Xcode 16 或更新版本的 macOS
- iOS 18 模拟器或真机

打开项目：

```bash
open Subly.xcodeproj
```

然后在 Xcode 中选择 `Subly` scheme 并运行。

命令行构建：

```bash
xcodebuild \
  -project Subly.xcodeproj \
  -scheme Subly \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  build
```

运行测试：

```bash
xcodebuild \
  -project Subly.xcodeproj \
  -scheme Subly \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  test
```

如果你的模拟器名称不同，可以在 Xcode 中查看可用设备后替换 `destination`。

## 项目结构

```text
Subly/
  App/                  App 入口、环境装配、根导航
  Core/                 领域模型、仓储协议、持久化模型、金额与日期工具
  Features/
    BackupRestore/      备份导出、导入与恢复逻辑
    BillingCycle/       账单周期与扣费日期计算
    CategoriesTemplates/分类管理与服务模板种子数据
    Currency/           汇率刷新与货币换算
    DesignSystem/       颜色、间距与通用组件
    Home/               首页仪表盘与订阅概览
    Reminders/          提醒计划生成与同步服务
    ServiceAggregation/ 服务聚合与汇总
    Settings/           偏好设置、备份恢复、分类入口
    Statistics/         图表与支出分析
    Subscriptions/      订阅表单、详情、命令与查询服务
SublyTests/             领域、仓储、服务和视图模型测试
```

## 架构说明

Subly 尽量让界面层保持轻薄，把主要行为放进清晰的小服务里：

- **领域模型** 描述订阅状态、账单周期、金额、提醒、日期区间、分类、设置和备份数据。
- **仓储层** 通过协议隔离 SwiftData 持久化细节。
- **服务层** 处理账单日期、统计、提醒、汇率换算、备份恢复和订阅写入操作。
- **视图模型** 为 SwiftUI 页面准备展示状态，并响应应用事件。

这样的结构让核心逻辑可以脱离完整 UI 流程进行测试。


## License

当前尚未声明开源许可证。

