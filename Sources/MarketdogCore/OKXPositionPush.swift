import Foundation

/// 只读私有 `positions` 推送的纯解析逻辑，可用真实报文测试而不建立连接。
public enum OKXPositionPush {
    public static func decode(_ data: Data) -> [OKXPositionRaw]? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arg = object["arg"] as? [String: Any],
              arg["channel"] as? String == "positions",
              let payload = object["data"] as? [[String: Any]] else { return nil }
        let instType = arg["instType"] as? String ?? "SWAP"
        return payload.compactMap { position in
            var fields = position
            if fields["instType"] == nil { fields["instType"] = instType }
            guard let encoded = try? JSONSerialization.data(withJSONObject: fields) else { return nil }
            return try? JSONDecoder().decode(OKXPositionRaw.self, from: encoded)
        }
    }
}
