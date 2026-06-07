import Foundation

enum CategorySeed {
    static let names = ["AI", "娱乐", "游戏", "工具", "云服务", "学习", "影音", "生活", "金融", "其他"]

    static func systemCategories(now: Date = Date()) -> [Category] {
        names.enumerated().map { index, name in
            Category(
                id: stableId("category.\(name)"),
                name: name,
                iconName: icon(for: name),
                colorToken: "category\(index)",
                sortOrder: index,
                isSystem: true,
                isArchived: false,
                createdAt: now,
                updatedAt: now
            )
        }
    }

    static func stableId(_ key: String) -> UUID {
        let known: [String: String] = [
            "category.AI": "10000000-0000-0000-0000-000000000001",
            "category.娱乐": "10000000-0000-0000-0000-000000000002",
            "category.游戏": "10000000-0000-0000-0000-000000000003",
            "category.工具": "10000000-0000-0000-0000-000000000004",
            "category.云服务": "10000000-0000-0000-0000-000000000005",
            "category.学习": "10000000-0000-0000-0000-000000000006",
            "category.影音": "10000000-0000-0000-0000-000000000007",
            "category.生活": "10000000-0000-0000-0000-000000000008",
            "category.金融": "10000000-0000-0000-0000-000000000009",
            "category.其他": "10000000-0000-0000-0000-000000000010",
            "template.chatgpt": "20000000-0000-0000-0000-000000000001",
            "template.claude": "20000000-0000-0000-0000-000000000002",
            "template.github-copilot": "20000000-0000-0000-0000-000000000003",
            "template.nintendo-switch-online": "20000000-0000-0000-0000-000000000004",
            "template.apple-music": "20000000-0000-0000-0000-000000000005",
            "template.apple-tv-plus": "20000000-0000-0000-0000-000000000006",
            "template.icloud-plus": "20000000-0000-0000-0000-000000000007",
            "template.netflix": "20000000-0000-0000-0000-000000000008",
            "template.spotify": "20000000-0000-0000-0000-000000000009",
            "template.youtube-premium": "20000000-0000-0000-0000-000000000010",
            "template.notion": "20000000-0000-0000-0000-000000000011",
            "template.cursor": "20000000-0000-0000-0000-000000000012",
            "template.office365": "20000000-0000-0000-0000-000000000013",
            "template.goodnotes": "20000000-0000-0000-0000-000000000014",
            "template.baidu-netdisk": "20000000-0000-0000-0000-000000000015",
            "template.qq-music": "20000000-0000-0000-0000-000000000016"
        ]
        return UUID(uuidString: known[key] ?? "ffffffff-ffff-ffff-ffff-ffffffffffff")!
    }

    private static func icon(for name: String) -> String {
        switch name {
        case "AI": "sparkles"
        case "娱乐": "play.tv"
        case "游戏": "gamecontroller"
        case "工具": "wrench.and.screwdriver"
        case "云服务": "icloud"
        case "学习": "book"
        case "影音": "music.note.tv"
        case "生活": "leaf"
        case "金融": "creditcard"
        default: "square.grid.2x2"
        }
    }
}

enum ServiceTemplateSeed {
    static func systemTemplates(categories: [Category], now: Date = Date()) -> [ServiceTemplate] {
        let byName = Dictionary(uniqueKeysWithValues: categories.map { ($0.name, $0.id) })
        let rows: [(String, String, String, BillingCycle, CurrencyCode, String)] = [
            ("ChatGPT", "chatgpt", "AI", .monthly, .USD, "sparkles"),
            ("Claude", "claude", "AI", .monthly, .USD, "sparkles.rectangle.stack"),
            ("GitHub Copilot", "github-copilot", "工具", .monthly, .USD, "chevron.left.forwardslash.chevron.right"),
            ("Nintendo Switch Online", "nintendo-switch-online", "游戏", .yearly, .USD, "gamecontroller"),
            ("Apple Music", "apple-music", "影音", .monthly, .CNY, "music.note"),
            ("Apple TV+", "apple-tv-plus", "影音", .monthly, .CNY, "play.tv"),
            ("iCloud+", "icloud-plus", "云服务", .monthly, .CNY, "icloud"),
            ("Netflix", "netflix", "娱乐", .monthly, .USD, "popcorn"),
            ("Spotify", "spotify", "影音", .monthly, .USD, "music.quarternote.3"),
            ("YouTube Premium", "youtube-premium", "娱乐", .monthly, .USD, "play.rectangle"),
            ("Notion", "notion", "工具", .monthly, .USD, "doc.text"),
            ("Cursor", "cursor", "AI", .monthly, .USD, "cursorarrow.click"),
            ("Office365", "office365", "工具", .monthly, .CNY, "doc.on.doc"),
            ("GoodNotes", "goodnotes", "学习", .yearly, .CNY, "pencil.and.outline"),
            ("Baidu Netdisk", "baidu-netdisk", "云服务", .monthly, .CNY, "externaldrive.connected.to.line.below"),
            ("QQ Music", "qq-music", "影音", .monthly, .CNY, "music.note")
        ]
        return rows.enumerated().map { index, row in
            ServiceTemplate(
                id: CategorySeed.stableId("template.\(row.1)"),
                serviceName: row.0,
                serviceKey: row.1,
                categoryId: byName[row.2] ?? byName["其他"]!,
                defaultCurrency: row.4,
                defaultCycle: row.3,
                iconStyle: IconStyle(systemName: row.5, colorToken: "template\(index)"),
                note: nil,
                websiteURL: nil,
                isSystem: true,
                sortOrder: index,
                createdAt: now,
                updatedAt: now
            )
        }
    }
}
