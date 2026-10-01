import Foundation
import Testing
@testable import MarketdogCore

@Suite struct CoinIconCatalogTests {
    @Test func namedAssetsUseProjectImagesFirst() {
        let hype = CoinIconCatalog.imageURLs(for: "HYPE-SWAP")
        let apt = CoinIconCatalog.imageURLs(for: "APT-USDT")
        #expect(hype.first?.absoluteString.contains("hyperliquid-dex.png") == true)
        #expect(apt.first?.absoluteString.contains("aptos_round.png") == true)
        #expect(apt.count >= 2)
    }

    @Test func aliasesAndInvalidNames() {
        #expect(CoinIconCatalog.imageURLs(for: "WETH").first?.lastPathComponent == "eth.png")
        #expect(CoinIconCatalog.imageURLs(for: "../../oops").isEmpty)
    }
}
