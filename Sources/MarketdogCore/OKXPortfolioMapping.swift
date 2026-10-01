import Foundation

public enum OKXPositionDirection: Sendable {
    case long
    case short
}

/// 与 UI 无关的合约持仓数据；macOS 和 iOS 只负责把它投影到各自的卡片模型。
public struct OKXMappedPosition: Sendable {
    public let key: String
    public let symbol: String
    public let direction: OKXPositionDirection
    public let quantity: Double
    public let averagePrice: Double?
    public let markPrice: Double?
    public let profitUSD: Double?
    public let profitRatio: Double?
    public let valueUSD: Double?
    public let leverage: String?
    public let liquidationPrice: Double?
    public let breakevenPrice: Double?
    public let marginRatio: Double?
    public let margin: Double?
    public let marginMode: String?
    public let maintenanceMargin: Double?
    public let initialMargin: Double?
    public let lastPrice: Double?
    public let indexPrice: Double?
    public let availableQuantity: Double?
    public let adl: String?
    public let realizedPnl: Double?
    public let fee: Double?
    public let fundingFee: Double?
    public let marginCurrency: String?
    public let positionID: String?
}

public struct OKXMappedSpot: Sendable {
    public let currency: String
    public let quantity: Double
    public let availableQuantity: Double?
    public let valueUSD: Double?
    public let profitUSD: Double?
}

public struct OKXMappedEarn: Sendable {
    public enum Kind: Sendable {
        case flexible
        case onChain
    }

    public let id: String
    public let currency: String
    public let quantity: Double
    public let valueUSD: Double?
    public let kind: Kind
}

public enum OKXPortfolioMapping {
    /// REST 快照和私有 WebSocket 增量共用同一个稳定键；平仓时也能找到旧持仓。
    public static func positionKey(_ raw: OKXPositionRaw) -> String {
        "\(raw.instType)-\(raw.instId)-\(raw.posSide ?? "net")"
    }

    public static func contract(_ raw: OKXPositionRaw) -> OKXMappedPosition? {
        guard let quantity = raw.pos.flatMap(Double.init), quantity != 0 else { return nil }
        let direction: OKXPositionDirection
        switch raw.posSide {
        case "long": direction = .long
        case "short": direction = .short
        default: direction = quantity >= 0 ? .long : .short
        }
        return OKXMappedPosition(
            key: positionKey(raw),
            symbol: raw.instId,
            direction: direction,
            quantity: abs(quantity),
            averagePrice: raw.avgPx.flatMap(Double.init),
            markPrice: raw.markPx.flatMap(Double.init),
            profitUSD: raw.upl.flatMap(Double.init),
            profitRatio: raw.uplRatio.flatMap(Double.init),
            valueUSD: raw.notionalUsd.flatMap(Double.init).map(abs),
            leverage: raw.lever,
            liquidationPrice: raw.liqPx.flatMap(Double.init),
            breakevenPrice: raw.bePx.flatMap(Double.init),
            marginRatio: raw.mgnRatio.flatMap(Double.init),
            margin: raw.margin.flatMap(Double.init),
            marginMode: raw.mgnMode,
            maintenanceMargin: raw.mmr.flatMap(Double.init),
            initialMargin: raw.imr.flatMap(Double.init),
            lastPrice: raw.last.flatMap(Double.init),
            indexPrice: raw.idxPx.flatMap(Double.init),
            availableQuantity: raw.availPos.flatMap(Double.init),
            adl: raw.adl,
            realizedPnl: raw.realizedPnl.flatMap(Double.init),
            fee: raw.fee.flatMap(Double.init),
            fundingFee: raw.fundingFee.flatMap(Double.init),
            marginCurrency: raw.ccy,
            positionID: raw.posId
        )
    }

    public static func spots(_ balances: [OKXBalanceRaw]) -> [OKXMappedSpot] {
        balances.flatMap(\.details).compactMap { detail in
            guard let quantity = detail.eq.flatMap(Double.init), quantity > 0 else { return nil }
            return OKXMappedSpot(
                currency: detail.ccy,
                quantity: quantity,
                availableQuantity: detail.availBal.flatMap(Double.init),
                valueUSD: detail.eqUsd.flatMap(Double.init),
                profitUSD: detail.upl.flatMap(Double.init)
            )
        }
    }

    public static func flexibleEarn(_ balances: [OKXSavingsBalanceRaw]) -> [OKXMappedEarn] {
        balances.compactMap { balance in
            guard let quantity = Double(balance.amt), quantity.isFinite, quantity > 0 else { return nil }
            return OKXMappedEarn(id: "flexible-\(balance.ccy)", currency: balance.ccy,
                                 quantity: quantity, valueUSD: nil, kind: .flexible)
        }
    }

    public static func onChainEarn(_ orders: [OKXOnChainEarnOrderRaw]) -> [OKXMappedEarn] {
        orders.flatMap { order in
            order.investData.compactMap { investment in
                guard let quantity = Double(investment.amt), quantity.isFinite, quantity > 0 else { return nil }
                return OKXMappedEarn(id: "onchain-\(order.ordId)-\(investment.ccy)",
                                     currency: investment.ccy, quantity: quantity,
                                     valueUSD: nil, kind: .onChain)
            }
        }
    }
}
