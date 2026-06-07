import Foundation

enum ValidationError: Error, Equatable, LocalizedError {
    case emptyName
    case invalidAmount
    case invalidCurrency
    case invalidBillingCycle
    case invalidDateRange
    case invalidURL
    case missingPaidCurrency
    case missingCategory
    case invalidReminderOffset

    var errorDescription: String? {
        switch self {
        case .emptyName: "名称不能为空"
        case .invalidAmount: "金额不合法"
        case .invalidCurrency: "币种不受支持"
        case .invalidBillingCycle: "订阅周期不合法"
        case .invalidDateRange: "日期范围不合法"
        case .invalidURL: "链接不合法"
        case .missingPaidCurrency: "实际支付币种缺失"
        case .missingCategory: "分类缺失"
        case .invalidReminderOffset: "提醒时间不合法"
        }
    }
}

enum SublyError: Error, Equatable, LocalizedError {
    case validation(ValidationError)
    case persistence(String)
    case missingExchangeRate(base: CurrencyCode, target: CurrencyCode)
    case notificationPermissionDenied
    case backupInvalid(String)
    case restoreFailed(String)
    case network(String)
    case networkUnavailable
    case invalidOperation(String)

    var errorDescription: String? {
        switch self {
        case .validation(let error):
            error.localizedDescription
        case .persistence(let message):
            "数据保存失败：\(message)"
        case .missingExchangeRate(let base, let target):
            "缺少 \(base.rawValue) 到 \(target.rawValue) 的汇率"
        case .notificationPermissionDenied:
            "通知权限未开启"
        case .backupInvalid(let message):
            "备份文件无效：\(message)"
        case .restoreFailed(let message):
            "恢复失败：\(message)"
        case .network(let message):
            "网络请求失败：\(message)"
        case .networkUnavailable:
            "网络不可用"
        case .invalidOperation(let message):
            message
        }
    }
}
