import Foundation

public struct OKXPortfolioSnapshot: Sendable {
    public let positions: [OKXMappedPosition]
    public let spots: [OKXMappedSpot]
    public let gridAlgos: [OKXMappedGridAlgo]
    public let totalEquityUSD: Double?

    public init(positions: [OKXMappedPosition], spots: [OKXMappedSpot], gridAlgos: [OKXMappedGridAlgo], totalEquityUSD: Double?) {
        self.positions = positions
        self.spots = spots
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
    public let gridAlgos: Bool

    public init(positions: Bool = true, spots: Bool = true, gridAlgos: Bool = false) {
        self.positions = positions
        self.spots = spots
        self.gridAlgos = gridAlgos
    }
}

/// OKX 请求编排和业务映射均留在 Core；App 只投影为平台专属展示模型。
public struct OKXPortfolioService: Sendable {
    private let client: OKXClient

    public init(credentials: OKXClient.Credentials) {
        client = OKXClient { credentials }
    }

    public func fetch(selection: OKXPortfolioSelection = .init()) async throws -> OKXPortfolioSnapshot {
        // 权益始终取一次；只显示合约时也不能丢失账户总权益。
        async let positions = selection.positions ? client.fetchPositions() : []
        async let balances = client.fetchBalance()
        let (rawPositions, rawBalances) = try await (positions, balances)
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
            totalEquityUSD: rawBalances.first?.totalEq.flatMap(Double.init)
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
