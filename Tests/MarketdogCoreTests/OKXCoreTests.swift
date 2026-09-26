import Foundation
import Testing

@testable import MarketdogCore

@Test func decodesBalanceResponse() throws {
    let json = Data(#"{"code":"0","msg":"","data":[{"totalEq":"123","details":[{"ccy":"BTC","eq":"1"}]}]}"#.utf8)
    let response = try JSONDecoder().decode(OKXResponse<OKXBalanceRaw>.self, from: json)
    #expect(response.code == "0")
    #expect(response.data.first?.details.first?.ccy == "BTC")
}

@Test func retryableExchangeError() {
    #expect(ExchangeError.httpError(429, "").isRetryable)
    #expect(!ExchangeError.httpError(401, "").isRetryable)
}

@Test func mapsContractAndClosedPositionConsistently() throws {
    let open = Data(#"{"instType":"SWAP","instId":"BTC-USDT-SWAP","pos":"-2","posSide":"net","notionalUsd":"-200","upl":"5","markPx":"72000"}"#.utf8)
    let raw = try JSONDecoder().decode(OKXPositionRaw.self, from: open)
    let mapped = try #require(OKXPortfolioMapping.contract(raw))
    #expect(mapped.key == "SWAP-BTC-USDT-SWAP-net")
    #expect(mapped.direction == .short)
    #expect(mapped.quantity == 2)
    #expect(mapped.valueUSD == 200)
    #expect(mapped.markPrice == 72000)

    let closed = Data(#"{"instType":"SWAP","instId":"BTC-USDT-SWAP","pos":"0","posSide":"net"}"#.utf8)
    let closedRaw = try JSONDecoder().decode(OKXPositionRaw.self, from: closed)
    #expect(OKXPortfolioMapping.positionKey(closedRaw) == mapped.key)
    #expect(OKXPortfolioMapping.contract(closedRaw) == nil)
}

@Test func keepsEveryPositiveSpotBalance() throws {
    let json = Data(#"{"totalEq":"1","details":[{"ccy":"APT","eq":"0.000001","eqUsd":"0.1"},{"ccy":"ARB","eq":"0"}]}"#.utf8)
    let balance = try JSONDecoder().decode(OKXBalanceRaw.self, from: json)
    let spots = OKXPortfolioMapping.spots([balance])
    #expect(spots.map(\.currency) == ["APT"])
}

@Test func decodesLiveTickerWithThreeChangeBases() throws {
    let push = Data(#"{"arg":{"channel":"tickers","instId":"BTC-USDT"},"data":[{"instId":"BTC-USDT","last":"72000","open24h":"70000","sodUtc0":"71000","sodUtc8":"71500"}]}"#.utf8)
    let update = try #require(OKXMarketData.decodeTickerPush(push))
    #expect(update.instrumentID == "BTC-USDT")
    #expect(update.change.lastPrice == 72000)
    #expect(abs((update.change.rolling24hRatio ?? 0) - 2_000.0 / 70_000.0) < 0.000001)
    #expect(OKXMarketData.decodeTickerPush(Data(#"{"event":"subscribe"}"#.utf8)) == nil)
}

@Test func decodesPrivatePositionPushWithoutDuplicatingInstrumentType() throws {
    let push = Data(#"{"arg":{"channel":"positions","instType":"SWAP"},"data":[{"instId":"ETH-USDT-SWAP","pos":"0","posSide":"long"}]}"#.utf8)
    let position = try #require(OKXPositionPush.decode(push)?.first)
    #expect(position.instType == "SWAP")
    #expect(position.pos == "0")
    #expect(OKXPortfolioMapping.contract(position) == nil)
}
