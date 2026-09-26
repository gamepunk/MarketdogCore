import Foundation

/// 公开行情连接；订阅增量、重连和 OKX 推送解析只实现一次。
@MainActor
public final class OKXPublicTickerStream {
    public var onUpdate: ((OKXTickerUpdate) -> Void)?
    public var onStateChange: ((String) -> Void)?

    private var socket: PlatformWebSocket?
    private var instrumentIDs: [String] = []

    public init() {}

    public func setInstrumentIDs(_ ids: [String]) {
        let normalized = Array(Set(ids)).sorted()
        let previous = instrumentIDs
        instrumentIDs = normalized
        guard let socket, previous != normalized else { return }
        let added = normalized.filter { !previous.contains($0) }
        let removed = previous.filter { !normalized.contains($0) }
        Task {
            if !added.isEmpty { await socket.send(Self.subscription(op: "subscribe", ids: added)) }
            if !removed.isEmpty { await socket.send(Self.subscription(op: "unsubscribe", ids: removed)) }
        }
    }

    public func connect() {
        guard socket == nil else { return }
        let stream = PlatformWebSocket(config: .init(
            url: "wss://ws.okx.com:8443/ws/v5/public",
            login: nil,
            subscribe: { [weak self] in
                guard let self, !self.instrumentIDs.isEmpty else { return nil }
                return Self.subscription(op: "subscribe", ids: self.instrumentIDs)
            },
            pingPayload: "ping",
            pingInterval: .seconds(20),
            onMessage: { [weak self] object in
                guard let data = try? JSONSerialization.data(withJSONObject: object),
                      let update = OKXMarketData.decodeTickerPush(data) else { return }
                self?.onUpdate?(update)
            },
            onStateChange: { [weak self] state in self?.onStateChange?(state) }
        ))
        socket = stream
        stream.connect()
    }

    public func stop() {
        socket?.stop()
        socket = nil
    }

    public nonisolated static func subscription(op: String, ids: [String]) -> [String: Any] {
        ["op": op, "args": ids.map { ["channel": "tickers", "instId": $0] }]
    }
}
