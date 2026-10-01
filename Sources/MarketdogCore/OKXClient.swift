import Foundation
import CryptoKit

/// OKX v5 API 客户端：负责签名、发请求、解析返回值。
/// 参考文档: https://www.okx.com/docs-v5/zh/#overview-rest-authentication
public final class OKXClient: Sendable {
    public struct Credentials: Sendable {
        public let apiKey: String
        public let secretKey: String
        public let passphrase: String
        /// 是否使用模拟盘（Demo Trading），对应 header: x-simulated-trading: 1
        public let simulated: Bool

        public init(apiKey: String, secretKey: String, passphrase: String, simulated: Bool) {
            self.apiKey = apiKey
            self.secretKey = secretKey
            self.passphrase = passphrase
            self.simulated = simulated
        }
    }

    private let baseURLString = "https://www.okx.com"
    private let session: URLSession
    private let credentialsProvider: @Sendable () -> Credentials?

    public init(session: URLSession = .shared, credentialsProvider: @escaping @Sendable () -> Credentials?) {
        self.session = session
        self.credentialsProvider = credentialsProvider
    }

    // MARK: - 业务接口

    /// 合约 / 保证金持仓，一次拿全部 instType（SWAP / FUTURES / MARGIN / OPTION）
    public func fetchPositions() async throws -> [OKXPositionRaw] {
        try await get(path: "/api/v5/account/positions")
    }

    /// 账户余额，用来展示现货持仓（币种数量 + 折算 USD 价值）
    public func fetchBalance() async throws -> [OKXBalanceRaw] {
        try await get(path: "/api/v5/account/balance")
    }

    /// 简单赚币活期余额；与交易账户余额分开，不能从 /account/balance 推断。
    public func fetchSavingsBalance() async throws -> [OKXSavingsBalanceRaw] {
        try await get(path: "/api/v5/finance/savings/balance")
    }

    /// 链上赚币/质押的进行中订单。只读，不调用申购或赎回接口。
    public func fetchOnChainEarnOrders() async throws -> [OKXOnChainEarnOrderRaw] {
        var orders: [OKXOnChainEarnOrderRaw] = []
        var after: String?
        // OKX limits this endpoint to 100 records per request. Follow `after`
        // until the final page so smaller earn positions are not silently lost.
        for _ in 0..<20 {
            var query = [URLQueryItem(name: "limit", value: "100")]
            if let after { query.append(URLQueryItem(name: "after", value: after)) }
            let page: [OKXOnChainEarnOrderRaw] = try await get(
                path: "/api/v5/finance/staking-defi/orders-active",
                queryItems: query
            )
            orders.append(contentsOf: page)
            guard page.count == 100, let last = page.last?.ordId, last != after else { break }
            after = last
        }
        return orders
    }

    /// OKX 对交易、资金、赚币等账户进行统一估值；由服务端将各币种折算成 USDT。
    public func fetchAssetValuationUSDT() async throws -> OKXAssetValuationRaw {
        let items: [OKXAssetValuationRaw] = try await get(
            path: "/api/v5/asset/asset-valuation",
            queryItems: [URLQueryItem(name: "ccy", value: "USDT")]
        )
        guard let valuation = items.first else {
            throw ExchangeError.apiError(code: "empty", message: "账户资产估值无数据")
        }
        return valuation
    }

    /// 策略机器人（网格 / 合约网格）当前运行中的持仓
    public func fetchGridAlgos(type: String) async throws -> [OKXGridAlgoRaw] {
        try await get(
            path: "/api/v5/tradingBot/grid/orders-algo-pending",
            queryItems: [URLQueryItem(name: "algoOrdType", value: type)]
        )
    }

    /// 用一个轻量接口校验 API Key 是否有效（读权限即可）
    public func testConnection() async throws {
        _ = try await get(path: "/api/v5/account/config") as [OKXAccountConfigRaw]
    }

    /// 单个交易对的行情（公开数据，不需要签名）。
    /// 一次只查一个 instId：持仓数量通常很少，比拉全部 478 个 SWAP ticker（约 140KB）划算。
    public func fetchTicker(instId: String) async throws -> OKXTickerRaw {
        let items: [OKXTickerRaw] = try await getPublic(
            path: "/api/v5/market/ticker",
            queryItems: [URLQueryItem(name: "instId", value: instId)]
        )
        guard let ticker = items.first else {
            throw ExchangeError.apiError(code: "empty", message: "行情无数据")
        }
        return ticker
    }

    /// 批量现货行情，供赚币资产折算为 USDT；不需要 API 凭证。
    public func fetchSpotTickers() async throws -> [OKXTickerRaw] {
        try await getPublic(path: "/api/v5/market/tickers", queryItems: [
            URLQueryItem(name: "instType", value: "SPOT")
        ])
    }

    // MARK: - 核心请求 + 签名

    /// 带重试的 GET：限流 / 服务端临时错误时退避重试（最多 2 次）。
    private func get<T: Decodable>(path: String, queryItems: [URLQueryItem] = []) async throws -> [T] {
        var attempt = 0
        while true {
            do {
                return try await performGet(path: path, queryItems: queryItems)
            } catch let error as ExchangeError where error.isRetryable && attempt < Self.maxRetries {
                attempt += 1
                try? await Task.sleep(for: .seconds(Self.retryDelay(forAttempt: attempt)))
            }
        }
    }

    private static let maxRetries = 2

    /// 退避间隔：0.4s、1.2s
    private static func retryDelay(forAttempt attempt: Int) -> Double {
        0.4 * pow(3, Double(attempt - 1))
    }

    private func performGet<T: Decodable>(path: String, queryItems: [URLQueryItem] = []) async throws -> [T] {
        guard let credentials = credentialsProvider() else {
            throw ExchangeError.missingCredentials
        }

        guard var components = URLComponents(string: baseURLString + path) else {
            throw ExchangeError.invalidURL
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else { throw ExchangeError.invalidURL }

        let queryString = queryItems.isEmpty
            ? ""
            : "?" + queryItems.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
        let requestPath = path + queryString

        let timestamp = Self.isoTimestamp()
        let signaturePayload = timestamp + "GET" + requestPath
        let signature = Self.sign(message: signaturePayload, secret: credentials.secretKey)

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(credentials.apiKey, forHTTPHeaderField: "OK-ACCESS-KEY")
        request.setValue(signature, forHTTPHeaderField: "OK-ACCESS-SIGN")
        request.setValue(timestamp, forHTTPHeaderField: "OK-ACCESS-TIMESTAMP")
        request.setValue(credentials.passphrase, forHTTPHeaderField: "OK-ACCESS-PASSPHRASE")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if credentials.simulated {
            request.setValue("1", forHTTPHeaderField: "x-simulated-trading")
        }

        return try await send(request)
    }

    /// 公开接口的 GET：不带签名头（行情类接口不需要凭证），也不重试。
    /// 行情丢一次无所谓，下一轮刷新会补上。
    private func getPublic<T: Decodable>(path: String, queryItems: [URLQueryItem]) async throws -> [T] {
        guard var components = URLComponents(string: baseURLString + path) else {
            throw ExchangeError.invalidURL
        }
        components.queryItems = queryItems
        guard let url = components.url else { throw ExchangeError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        return try await send(request)
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> [T] {
        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw ExchangeError.httpError(-1, "无响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ExchangeError.httpError(http.statusCode, body)
        }

        do {
            let decoded = try JSONDecoder().decode(OKXResponse<T>.self, from: data)
            guard decoded.code == "0" else {
                throw ExchangeError.apiError(code: decoded.code, message: decoded.msg)
            }
            return decoded.data
        } catch let error as ExchangeError {
            throw error
        } catch {
            throw ExchangeError.decodingError(error)
        }
    }

    // MARK: - 签名工具

    private static func isoTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }

    private static func sign(message: String, secret: String) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        return Data(mac).base64EncodedString()
    }
}

/// 仅用来校验 API Key 有效性的最小化模型
struct OKXAccountConfigRaw: Decodable {
    let uid: String?
}
