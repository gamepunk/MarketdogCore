import Foundation

/// 版本化的跨设备凭证二维码内容。注意：Base64 仅是编码，并非加密。
public struct OKXCredentialTransfer: Codable, Equatable, Sendable {
    public static let prefix = "marketdog-credential:v1:"

    public let name: String
    public let apiKey: String
    public let secretKey: String
    public let passphrase: String
    public let simulated: Bool

    public init(name: String, apiKey: String, secretKey: String, passphrase: String, simulated: Bool) {
        self.name = name
        self.apiKey = apiKey
        self.secretKey = secretKey
        self.passphrase = passphrase
        self.simulated = simulated
    }

    public var isComplete: Bool {
        !apiKey.isEmpty && !secretKey.isEmpty && !passphrase.isEmpty
    }

    public func encode() throws -> String {
        guard isComplete else { throw TransferError.incomplete }
        let data = try JSONEncoder().encode(self)
        guard data.count <= 3_000 else { throw TransferError.tooLarge }
        let base64 = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return Self.prefix + base64
    }

    public static func decode(_ text: String) throws -> Self {
        guard text.hasPrefix(prefix) else { throw TransferError.unsupportedFormat }
        let encoded = String(text.dropFirst(prefix.count))
        guard !encoded.isEmpty, encoded.count <= 4_000,
              encoded.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
        else { throw TransferError.invalidData }
        let standard = encoded.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padded = standard + String(repeating: "=", count: (4 - standard.count % 4) % 4)
        guard let data = Data(base64Encoded: padded), data.count <= 3_000,
              let payload = try? JSONDecoder().decode(Self.self, from: data), payload.isComplete
        else { throw TransferError.invalidData }
        return payload
    }

    public enum TransferError: LocalizedError {
        case incomplete
        case tooLarge
        case unsupportedFormat
        case invalidData

        public var errorDescription: String? {
            switch self {
            case .incomplete: "API 凭证未填写完整"
            case .tooLarge: "凭证内容过长，无法生成二维码"
            case .unsupportedFormat: "不是看盘狗凭证二维码，或格式版本不受支持"
            case .invalidData: "二维码内容无效或已损坏"
            }
        }
    }
}
