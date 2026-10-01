import Foundation

public struct OKXPortfolioSnapshot: Sendable {
    public let positions: [OKXMappedPosition]
    public let spots: [OKXMappedSpot]
    public let earns: [OKXMappedEarn]
    public let warnings: [String]
    public let gridAlgos: [OKXMappedGridAlgo]
    public let totalEquityUSD: Double?

    public init(positions: [OKXMappedPosition], spots: [OKXMappedSpot], gridAlgos: [OKXMappedGridAlgo], totalEquityUSD: Double?, earns: [OKXMappedEarn] = [], warnings: [String] = []) {
        self.positions = positions
        self.spots = spots
        self.earns = earns
        self.warnings = warnings
        self.gridAlgos = gridAlgos
        self.totalEquityUSD = totalEquityUSD
    }
}

public struct OKXMappedGridAlgo: Sendable {
    public let id: String
    public let symbol: String
    public let type: String
    public let profitUSD: Double?
    public let profitRatio: Double?
    public let investmentUSD: Double?
}

public struct OKXPortfolioSelection: Sendable {
    public let positions: Bool
    public let spots: Bool
    public let earns: Bool
    public let gridAlgos: Bool

    public init(positions: Bool = true, spots: Bool = true, gridAlgos: Bool = false, earns: Bool = false) {
        self.positions = positions
        self.spots = spots
        self.earns = earns
        self.gridAlgos = gridAlgos
    }
}

/// OKX 请求编排和业务映射均留在 Core；App 只投影为平台专属展示模型。
public struct OKXPortfolioService: Sendable {
    private let client: OKXClient
    private let valuationKey: String
    private static let earnPrices = OKXEarnPriceCache()
    private static let valuationCache = OKXValuationCache()

    public init(credentials: OKXClient.Credentials) {
        client = OKXClient { credentials }
        valuationKey = "\(credentials.simulated)-\(credentials.apiKey)"
    }

    public func fetch(selection: OKXPortfolioSelection = .init()) async throws -> OKXPortfolioSnapshot {
        // 权益始终取一次；只显示合约时也不能丢失账户总权益。
        async let positions = selection.positions ? client.fetchPositions() : []
        let rawBalances: [OKXBalanceRaw]
        if selection.spots {
            rawBalances = try await client.fetchBalance()
        } else {
            // 仅显示合约时，总权益是附加信息；余额接口失败不应隐藏持仓。
            rawBalances = (try? await client.fetchBalance()) ?? []
        }
        let rawPositions = try await positions
        var earns: [OKXMappedEarn] = []
        var warnings: [String] = []
        if selection.earns {
            // 赚币权限/产品可能不可用；单个产品失败不应隐藏交易账户资产。
            async let flexible = client.fetchSavingsBalance()
            async let onChain = client.fetchOnChainEarnOrders()
            do { earns += OKXPortfolioMapping.flexibleEarn(try await flexible) }
            catch { warnings.append("简单赚币读取失败：\(error.localizedDescription)") }
            do { earns += OKXPortfolioMapping.onChainEarn(try await onChain) }
            catch { warnings.append("链上赚币读取失败：\(error.localizedDescription)") }
            if !earns.isEmpty {
                let prices = await Self.earnPrices.prices()
                earns = earns.map { asset in
                    OKXMappedEarn(id: asset.id, currency: asset.currency,
                                  quantity: asset.quantity,
                                  valueUSD: prices[asset.currency].map { $0 * asset.quantity },
                                  kind: asset.kind)
                }
            }
        }
        var grids: [OKXMappedGridAlgo] = []
        if selection.gridAlgos {
            // 策略权限可能未开通，不应让它阻断普通持仓。
            for type in ["grid", "contract_grid"] {
                if let raw = try? await client.fetchGridAlgos(type: type) {
                    grids += Self.mapGridAlgos(raw, type: type)
                }
            }
        }
        return OKXPortfolioSnapshot(
            positions: rawPositions.compactMap(OKXPortfolioMapping.contract),
            spots: selection.spots ? OKXPortfolioMapping.spots(rawBalances) : [],
            gridAlgos: grids,
            totalEquityUSD: await Self.valuationCache.totalUSD(for: valuationKey, client: client)
                ?? rawBalances.first?.totalEq.flatMap(Double.init),
            earns: earns,
            warnings: warnings
        )
    }

    public static func mapGridAlgos(_ raws: [OKXGridAlgoRaw], type: String) -> [OKXMappedGridAlgo] {
        raws.map { raw in
            OKXMappedGridAlgo(
                id: raw.algoId,
                symbol: raw.instId,
                type: type,
                profitUSD: raw.totalPnl.flatMap(Double.init) ?? raw.floatProfit.flatMap(Double.init),
                profitRatio: raw.pnlRatio.flatMap(Double.init),
                investmentUSD: raw.investment.flatMap(Double.init)
            )
        }
    }
}

/// 全资产估值接口按用户每秒只允许一次请求；短刷新间隔下复用最近的成功值。
private actor OKXValuationCache {
    private var values: [String: (date: Date, total: Double)] = [:]

    func totalUSD(for key: String, client: OKXClient) async -> Double? {
        let previous = values[key]
        if let previous, Date().timeIntervalSince(previous.date) < 30 { return previous.total }
        guard let total = try? await client.fetchAssetValuationUSDT().totalUSDT else {
            return previous?.total
        }
        values[key] = (Date(), total)
        return total
    }
}

/// 行情公开接口限时缓存，避免短刷新间隔时每秒重复拉全市场现货报价。
private actor OKXEarnPriceCache {
    private let client = OKXClient { nil }
    private var cached: [String: Double] = ["USDT": 1]
    private var fetchedAt: Date = .distantPast

    func prices() async -> [String: Double] {
        guard Date().timeIntervalSince(fetchedAt) >= 60 else { return cached }
        guard let tickers = try? await client.fetchSpotTickers() else { return cached }
        var next: [String: Double] = ["USDT": 1]
        for ticker in tickers {
            guard let id = ticker.instId, id.hasSuffix("-USDT"),
                  let price = ticker.last.flatMap(Double.init), price.isFinite, price > 0
            else { continue }
            next[String(id.dropLast(5))] = price
        }
        cached = next
        fetchedAt = Date()
        return cached
    }
}

public struct OKXMarketService: Sendable {
    private let client = OKXClient { nil }
    private let batchSize = 8

    public init() {}

    public func fetchChanges(symbols: [String]) async -> [String: OKXMarketChange] {
        let unique = Array(Set(symbols)).sorted()
        var changes: [String: OKXMarketChange] = [:]
        for start in stride(from: 0, to: unique.count, by: batchSize) {
            let batch = Array(unique[start..<min(start + batchSize, unique.count)])
            await withTaskGroup(of: (String, OKXMarketChange?).self) { group in
                for symbol in batch {
                    group.addTask {
                        guard let ticker = try? await client.fetchTicker(instId: OKXMarketData.instrumentID(for: symbol)) else {
                            return (symbol, nil)
                        }
                        return (symbol, OKXMarketData.mapTicker(ticker))
                    }
                }
                for await (symbol, change) in group {
                    if let change { changes[symbol] = change }
                }
            }
        }
        return changes
    }
}
