import Foundation
import Testing

@testable import MarketdogCore

@Test func decodesBalanceResponse() throws {
    let json = Data(#"{"code":"0","msg":"","data":[{"totalEq":"123","details":[{"ccy":"BTC","eq":"1"}]}]}"#.utf8)
    let response = try JSONDecoder().decode(OKXResponse<OKXBalanceRaw>.self, from: json)
    #expect(response.code == "0")
    #expect(response.data.first?.details.first?.ccy == "BTC")
}

@Test func decodesAllAccountAssetValuationInUSDT() throws {
    let json = Data(#"{"code":"0","msg":"","data":[{"details":{"trading":"100","funding":"20","earn":"5"},"totalBal":"125.5"}]}"#.utf8)
    let response = try JSONDecoder().decode(OKXResponse<OKXAssetValuationRaw>.self, from: json)
    #expect(response.data.first?.totalUSDT == 125.5)
    #expect(response.data.first?.details?.funding == "20")
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

@Test func mapsBothEarnProductsWithoutMixingThemIntoTradingBalance() throws {
    let savings = try JSONDecoder().decode([OKXSavingsBalanceRaw].self, from: Data(
        #"[{"ccy":"APT","amt":"2.5"},{"ccy":"ETH","amt":"0"}]"#.utf8
    ))
    let orders = try JSONDecoder().decode([OKXOnChainEarnOrderRaw].self, from: Data(
        #"[{"ordId":"42","state":"1","protocolType":"defi","investData":[{"ccy":"APT","amt":"3"},{"ccy":"BTC","amt":"0.1"}]},{"ordId":"43","protocolType":"other","investData":[{"ccy":"ETH","amt":"1"}]}]"#.utf8
    ))
    let flexible = OKXPortfolioMapping.flexibleEarn(savings)
    let onChain = OKXPortfolioMapping.onChainEarn(orders)
    #expect(flexible.map(\.id) == ["flexible-APT"])
    #expect(onChain.map(\.id) == ["onchain-42-APT", "onchain-42-BTC", "onchain-43-ETH"])
    #expect(flexible.first?.quantity == 2.5)
    #expect(onChain.first?.quantity == 3)
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

@Test func mapsGridAnalysisInCore() throws {
    let data = Data(#"{"algoId":"123","algoOrdType":"grid","instId":"BTC-USDT","totalPnl":"12.5","pnlRatio":"0.1","investment":"125"}"#.utf8)
    let raw = try JSONDecoder().decode(OKXGridAlgoRaw.self, from: data)
    let mapped = try #require(OKXPortfolioService.mapGridAlgos([raw], type: "grid").first)
    #expect(mapped.id == "123")
    #expect(mapped.profitUSD == 12.5)
    #expect(mapped.profitRatio == 0.1)
    #expect(mapped.investmentUSD == 125)
}

@Test func buildsPublicTickerSubscriptionInCore() {
    let request = OKXPublicTickerStream.subscription(op: "subscribe", ids: ["BTC-USDT"])
    #expect(request["op"] as? String == "subscribe")
    let args = request["args"] as? [[String: String]]
    #expect(args?.first?["instId"] == "BTC-USDT")
}

@Test func sharesDisplayValueRulesAcrossApps() {
    #expect(OKXDisplayValues.primaryNumber(kind: .contract, livePrice: 72, markPrice: 71, lastPrice: 70, valueUSD: 100) == 72)
    #expect(OKXDisplayValues.primaryNumber(kind: .contract, livePrice: nil, markPrice: 71, lastPrice: 70, valueUSD: 100) == 71)
    #expect(OKXDisplayValues.primaryNumber(kind: .spot, livePrice: 72, markPrice: nil, lastPrice: nil, valueUSD: 100) == 100)
    #expect(OKXDisplayValues.primaryNumber(kind: .strategy, livePrice: nil, markPrice: nil, lastPrice: nil, valueUSD: 125) == 125)
    #expect(OKXDisplayValues.changeRatio(positionRatio: 0.1, rolling24hRatio: 0.2) == 0.1)
    #expect(OKXDisplayValues.changeRatio(positionRatio: nil, rolling24hRatio: 0.2) == 0.2)
}

@Test func sharesSpotWeightedAverageCost() {
    var basis = SpotCostBasis()
    basis.apply(.init(accountID: "a", currency: "BTC", kind: .buy, quantity: 1, unitPrice: 60_000))
    basis.apply(.init(accountID: "a", currency: "BTC", kind: .buy, quantity: 2, unitPrice: 75_000, fee: 30))
    #expect(basis.averagePrice == 70_010)
    basis.apply(.init(accountID: "a", currency: "BTC", kind: .sell, quantity: 1))
    #expect(basis.averagePrice == 70_010)
}

@Test func credentialQRRoundTripAndRejectsInvalidContent() throws {
    let original = OKXCredentialTransfer(name: "主账户", apiKey: "key", secretKey: "secret", passphrase: "pass", simulated: true)
    let encoded = try original.encode()
    #expect(try OKXCredentialTransfer.decode(encoded) == original)
    #expect(throws: OKXCredentialTransfer.TransferError.self) {
        try OKXCredentialTransfer.decode("https://example.com")
    }
    #expect(throws: OKXCredentialTransfer.TransferError.self) {
        try OKXCredentialTransfer(name: "", apiKey: "", secretKey: "", passphrase: "", simulated: false).encode()
    }
}
