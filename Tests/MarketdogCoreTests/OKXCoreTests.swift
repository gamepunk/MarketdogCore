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
