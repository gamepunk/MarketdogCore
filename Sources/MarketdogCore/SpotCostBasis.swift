import Foundation

/// 本地补录的现货变动；仅用于只读成本分析，不会提交给 OKX。
public struct SpotLedgerEntry: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case buy, sell, transferIn, transferOut, adjustment
    }

    public let id: UUID
    public var accountID: String
    public var currency: String
    public var kind: Kind
    public var quantity: Double
    public var unitPrice: Double?
    public var fee: Double
    public var date: Date
    public var note: String

    public init(id: UUID = UUID(), accountID: String, currency: String, kind: Kind,
                quantity: Double, unitPrice: Double? = nil, fee: Double = 0,
                date: Date = .now, note: String = "") {
        self.id = id
        self.accountID = accountID
        self.currency = currency.uppercased()
        self.kind = kind
        self.quantity = max(0, quantity)
        self.unitPrice = unitPrice
        self.fee = fee
        self.date = date
        self.note = note
    }
}

/// 移动加权平均成本；卖出/转出只减数量，不改剩余单位成本。
public struct SpotCostBasis: Equatable, Sendable {
    public var quantity: Double
    public var totalCost: Double

    public init(quantity: Double = 0, totalCost: Double = 0) {
        self.quantity = quantity
        self.totalCost = totalCost
    }

    public var averagePrice: Double? { quantity > 0 ? totalCost / quantity : nil }

    public mutating func apply(_ entry: SpotLedgerEntry) {
        switch entry.kind {
        case .buy, .transferIn, .adjustment:
            quantity += entry.quantity
            totalCost += entry.quantity * (entry.unitPrice ?? 0) + entry.fee
        case .sell, .transferOut:
            guard quantity > 0 else { return }
            let removed = min(quantity, entry.quantity)
            let unitCost = totalCost / quantity
            quantity -= removed
            totalCost = quantity == 0 ? 0 : max(0, totalCost - unitCost * removed)
        }
    }
}
