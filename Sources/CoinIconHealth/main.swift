import Foundation
import MarketdogCore

@main
struct CoinIconHealth {
    static func main() async {
        var failures: [String] = []
        if CoinIconCatalog.bundledImageURL(for: "BTC") == nil ||
           CoinIconCatalog.bundledImageURL(for: "APT") == nil ||
           CoinIconCatalog.bundledImageURL(for: "HYPE") == nil {
            failures.append("bundled Web3 Icons are missing")
        }
        for currency in CoinIconCatalog.explicitlyMappedCurrencies {
            guard let url = CoinIconCatalog.imageURLs(for: currency).first else {
                failures.append("\(currency): no configured image")
                continue
            }
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 15
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                let isPNG = data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
                guard status == 200, response.mimeType == "image/png",
                      !data.isEmpty, data.count <= 2_000_000, isPNG else {
                    failures.append("\(currency): invalid response (HTTP \(status)) at \(url)")
                    continue
                }
                print("OK \(currency): \(data.count) bytes")
            } catch {
                failures.append("\(currency): \(error.localizedDescription)")
            }
        }
        for failure in failures { fputs("FAIL \(failure)\n", stderr) }
        if !failures.isEmpty { exit(1) }
    }
}
