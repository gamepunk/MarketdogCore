import Foundation

public struct OKXMarketChange: Equatable, Sendable {
    public let lastPrice: Double?
    public let dayRatio: Double?
    public let utcDayRatio: Double?
    public let rolling24hRatio: Double?
}

public struct OKXTickerUpdate: Equatable, Sendable {
    public let instrumentID: String
    public let change: OKXMarketChange
}

public enum OKXMarketData {
    public static func instrumentID(for symbol: String) -> String {
        symbol.contains("-") ? symbol : "\(symbol)-USDT"
    }

    public static func ratio(last: Double?, base: Double?) -> Double? {
        guard let last, let base, base > 0 else { return nil }
        return (last - base) / base
    }

    public static func mapTicker(_ raw: OKXTickerRaw) -> OKXMarketChange {
        let last = raw.last.flatMap(Double.init)
        return OKXMarketChange(
            lastPrice: last,
            dayRatio: ratio(last: last, base: raw.sodUtc8.flatMap(Double.init)),
            utcDayRatio: ratio(last: last, base: raw.sodUtc0.flatMap(Double.init)),
            rolling24hRatio: ratio(last: last, base: raw.open24h.flatMap(Double.init))
        )
    }

    /// 订阅回执与 pong 不含行情，返回 nil；REST 和 WebSocket 共用上面的换算。
    public static func decodeTickerPush(_ data: Data) -> OKXTickerUpdate? {
        guard let push = try? JSONDecoder().decode(TickerPush.self, from: data),
              push.arg?.channel == "tickers",
              let ticker = push.data?.first,
              let instrumentID = ticker.instId else { return nil }
        return OKXTickerUpdate(instrumentID: instrumentID, change: mapTicker(ticker))
    }
}

private struct TickerPush: Decodable {
    struct Argument: Decodable { let channel: String }
    let arg: Argument?
    let data: [OKXTickerRaw]?
}
