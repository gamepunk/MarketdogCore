import Foundation

/// Stable asset identity and ordered image sources, shared by both apps.
/// The ticker is only a lookup key; it must not be treated as an image filename.
public enum CoinIconCatalog {
    private static let cdnBase = "https://cdn.jsdelivr.net/npm/cryptocurrency-icons@0.18.1/128/color"
    private static let aliases = [
        "XBT": "BTC", "WETH": "ETH", "WBTC": "BTC",
        "LUNA2": "LUNA", "BCHSV": "BSV"
    ]

    private static let namedSources: [String: [String]] = [
        "APT": [
            "https://assets.coingecko.com/coins/images/26455/large/aptos_round.png",
            "https://cryptologos.cc/logos/aptos-apt-logo.png"
        ],
        "HYPE": [
            "https://github.com/hyperliquid-dex.png?size=256",
            "https://raw.githubusercontent.com/ErikThiart/cryptocurrency-icons/master/128/hyperliquid.png"
        ]
    ]

    public static func currency(from instrument: String) -> String {
        String(instrument.split(separator: "-").first ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }

    public static func imageURLs(for instrument: String) -> [URL] {
        let currency = currency(from: instrument)
        guard !currency.isEmpty,
              currency.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) && $0.isASCII })
        else { return [] }

        let remoteCode = (aliases[currency] ?? currency).lowercased()
        let addresses = (namedSources[currency] ?? []) + ["\(cdnBase)/\(remoteCode).png"]
        return addresses.compactMap(URL.init(string:))
    }

    /// Mapped symbols for which the generic icon package is known to be incomplete.
    public static let explicitlyMappedCurrencies = ["APT", "HYPE"]
}
