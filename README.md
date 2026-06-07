# Subly

> A calm, local-first subscription tracker for iPhone.

[![Swift](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)](https://swift.org)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-iOS%2018-0A84FF?logo=apple&logoColor=white)](https://developer.apple.com/xcode/swiftui/)
[![Storage](https://img.shields.io/badge/Storage-SwiftData-34C759?logo=icloud&logoColor=white)](https://developer.apple.com/xcode/swiftdata/)
[![Status](https://img.shields.io/badge/Status-v1.0.0-informational)](#)

**English** · [简体中文](README.zh-CN.md)

Subly helps you keep recurring subscriptions visible before they quietly become surprises. Track billing cycles, renewal dates, paid currencies, reminders, category spending, and backup data in a focused SwiftUI app that keeps your data on device.

Built for people who want a small, fast subscription ledger instead of another heavy personal finance system.

## Highlights

- **Subscription ledger**: record active, paused, cancelled, trial, one-time, expired, and renewal-decision states.
- **Flexible billing cycles**: weekly, monthly, quarterly, half-yearly, yearly, custom-day, one-time, and trial plans.
- **Renewal reminders**: configurable default reminder offsets with per-subscription support.
- **Currency-aware costs**: CNY, USD, HKD, JPY, EUR, and GBP with primary display support for CNY and USD.
- **Spending insights**: category share, service rankings, monthly trends, and yearly trends powered by Swift Charts.
- **Categories and templates**: seed data plus editable categories for keeping subscriptions tidy.
- **Backup and restore**: JSON export/import flows with merge and overwrite restore modes.
- **Local-first architecture**: SwiftUI + SwiftData, with repository and service layers covered by tests.

## Screens

Subly is organized around three tabs:

- **Subscriptions**: dashboard summary, active/history scopes, upcoming renewals, and subscription details.
- **Statistics**: category spending, service ranking, monthly trend, and yearly trend.
- **Settings**: display currency, appearance, reminders, categories, backup, and restore.

## Tech Stack

- **Language**: Swift 6
- **UI**: SwiftUI
- **Persistence**: SwiftData
- **Charts**: Swift Charts
- **Notifications**: UserNotifications
- **Platform target**: iOS 18+
- **Project format**: Xcode project (`Subly.xcodeproj`)

## Quick Start

Requirements:

- macOS with Xcode 16 or newer
- iOS 18 simulator or device

Open the project:

```bash
open Subly.xcodeproj
```

Then choose the `Subly` scheme and run it from Xcode.

Command-line build:

```bash
xcodebuild \
  -project Subly.xcodeproj \
  -scheme Subly \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  build
```

Run tests:

```bash
xcodebuild \
  -project Subly.xcodeproj \
  -scheme Subly \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  test
```

If your simulator name differs, list available destinations from Xcode and replace the destination string.

## Project Structure

```text
Subly/
  App/                  App entry, environment wiring, root navigation
  Core/                 Domain models, repositories, persistence, money/date helpers
  Features/
    BackupRestore/      Backup export/import and restore logic
    BillingCycle/       Billing schedule calculation
    CategoriesTemplates/Category management and seed templates
    Currency/           Currency conversion and exchange-rate refresh
    DesignSystem/       Shared colors, spacing, components
    Home/               Dashboard and subscription overview
    Reminders/          Reminder generation and sync services
    ServiceAggregation/ Service-level grouping and summaries
    Settings/           Preferences, backup, restore, category entry points
    Statistics/         Charts and spending analysis
    Subscriptions/      Subscription forms, details, commands, queries
SublyTests/             Unit tests for domain, repositories, services, and view models
```

## Architecture

Subly keeps UI code thin and pushes behavior into small service layers:

- **Domain models** describe subscription status, billing cycles, money, reminders, date ranges, categories, settings, and backup payloads.
- **Repositories** isolate SwiftData persistence behind protocols.
- **Services** handle billing schedules, statistics, reminders, currency conversion, backup/restore, and subscription commands.
- **View models** prepare screen state for SwiftUI views and react to app events.

This makes the app easier to test without depending on full UI flows.


## License

No license has been declared yet.

