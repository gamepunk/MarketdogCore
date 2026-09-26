import Foundation

/// OKX v5 REST 接口统一返回结构：{ "code": "0", "msg": "", "data": [...] }
public struct OKXResponse<T: Decodable>: Decodable {
    public let code: String
    public let msg: String
    public let data: [T]
}

public enum ExchangeError: LocalizedError {
    case missingCredentials
    case invalidURL
    case httpError(Int, String)
    case apiError(code: String, message: String)
    case decodingError(Error)

    public var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "尚未配置 API Key，请在设置中填写"
        case .invalidURL:
            return "请求地址不合法"
        case .httpError(let status, let body):
            return "网络请求失败 (\(status)): \(body)"
        case .apiError(let code, let message):
            return "OKX 接口错误 [\(code)]: \(message)"
        case .decodingError(let error):
            return "数据解析失败: \(error.localizedDescription)"
        }
    }

    /// 是否值得重试：OKX 限流或服务端临时性错误。
    public var isRetryable: Bool {
        switch self {
        case .httpError(let status, _):
            return status == 408 || status == 429 || (500...599).contains(status)
        case .apiError(let code, _):
            return Self.retryableCodes.contains(code)
        default:
            return false
        }
    }

    /// 50011 请求过于频繁 / 50013 系统繁忙 / 50040 服务暂时不可用
    private static let retryableCodes: Set<String> = [
        "50011", "50013", "50040",
        "429"
    ]
}

// MARK: - 合约 / 保证金持仓 (/api/v5/account/positions)

public struct OKXPositionRaw: Decodable {
    public let instType: String
    public let instId: String
    public let mgnMode: String?
    public let posSide: String?
    public let pos: String?
    public let avgPx: String?
    public let markPx: String?
    public let upl: String?
    public let uplRatio: String?
    public let lever: String?
    public let notionalUsd: String?
    /// 预估强平价
    public let liqPx: String?
    /// 盈亏平衡价
    public let bePx: String?
    /// 维持保证金率（倍数，例如 11.73 代表 1173%）
    public let mgnRatio: String?
    /// 保证金，仅逐仓有值
    public let margin: String?
    /// 维持保证金（金额）
    public let mmr: String?
    /// 初始保证金（仅全仓有值）
    public let imr: String?
    /// 最新成交价
    public let last: String?
    /// 指数价格
    public let idxPx: String?
    public let ccy: String?
    /// 可平数量
    public let availPos: String?
    /// 自动减仓（ADL）等级
    public let adl: String?
    /// 已实现盈亏
    public let realizedPnl: String?
    /// 手续费（负数表示支出）
    public let fee: String?
    /// 资金费
    public let fundingFee: String?
    /// 持仓 ID
    public let posId: String?
}

// MARK: - 账户余额 / 现货持仓 (/api/v5/account/balance)

public struct OKXBalanceRaw: Decodable {
    public let totalEq: String?
    public let details: [OKXBalanceDetailRaw]
}

public struct OKXBalanceDetailRaw: Decodable {
    public let ccy: String
    public let eq: String?
    public let eqUsd: String?
    public let availBal: String?
    public let upl: String?
}

// MARK: - 策略机器人持仓 (/api/v5/tradingBot/grid/orders-algo-pending)

public struct OKXGridAlgoRaw: Decodable {
    public let algoId: String
    public let algoOrdType: String
    public let instId: String
    public let state: String?
    public let totalPnl: String?
    public let pnlRatio: String?
    public let floatProfit: String?
    public let gridProfit: String?
    public let investment: String?
}

/// 行情 ticker（`GET /api/v5/market/ticker`，公开接口）。
/// 实测字段：`last` 最新价、`open24h` 24 小时前开盘价、
/// `sodUtc0` / `sodUtc8` 分别是 UTC 0 点 / 北京时间 0 点的价格。
public struct OKXTickerRaw: Decodable {
    public let instId: String?
    public let last: String?
    public let open24h: String?
    public let sodUtc0: String?
    public let sodUtc8: String?
}
