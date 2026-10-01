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

    @Test func bundledWeb3IconsAreAvailable() {
        for symbol in ["BTC", "ETH", "APT", "HYPE", "ZEC", "ARB"] {
            let url = CoinIconCatalog.bundledImageURL(for: "\(symbol)-SWAP")
            #expect(url?.pathExtension == "svg")
            #expect(url.flatMap { try? Data(contentsOf: $0) }.map { !$0.isEmpty } == true)
        }
        #expect(CoinIconCatalog.bundledImageURL(for: "../oops") == nil)
    }

    @Test func aptUsesAptosLogomark() {
        #expect(CoinIconCatalog.bundledImageURL(for: "APT-SWAP")?.lastPathComponent == "APTOS.svg")
    }
}
