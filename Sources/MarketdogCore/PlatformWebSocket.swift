import CryptoKit
import Foundation

/// 通用私有 WebSocket：连接 → 登录 → 订阅 → 心跳 → 断线重连。
///
/// 各平台差异（地址、鉴权消息、订阅消息、心跳格式）由 `Config` 注入；
/// 收到的消息原样交给 `onMessage`，由各平台自己判断是不是持仓 / 账户变动。
@MainActor
public final class PlatformWebSocket {
    public struct Config {
        let url: String
        /// 登录消息；nil 表示该平台不需要登录（如币安的 listenKey 流）
        let login: (() -> [String: Any])?
        /// 订阅消息；返回 nil 表示这次不订阅
        let subscribe: () -> [String: Any]?
        /// 心跳内容；nil 表示不发应用层心跳
        let pingPayload: String?
        let pingInterval: Duration
        let onMessage: ([String: Any]) -> Void
        let onStateChange: (String) -> Void

        public init(
            url: String,
            login: (() -> [String: Any])?,
            subscribe: @escaping () -> [String: Any]?,
            pingPayload: String?,
            pingInterval: Duration,
            onMessage: @escaping ([String: Any]) -> Void,
            onStateChange: @escaping (String) -> Void
        ) {
            self.url = url
            self.login = login
            self.subscribe = subscribe
            self.pingPayload = pingPayload
            self.pingInterval = pingInterval
            self.onMessage = onMessage
            self.onStateChange = onStateChange
        }
    }

    private let config: Config
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var isStopped = true
    private var isReconnecting = false
    private var retryDelay: TimeInterval = 1
    /// 本轮连接建立的时刻，用来判断这条连接是不是「活够久了」
    private var connectedAt: Date?
    /// 连接活过这个时长才算稳定。连上就断（凭证错 / 被限流）不该把退避清零，
    /// 否则会退化成每秒重连、反复撞鉴权失败。
    private static let stableConnectionDuration: TimeInterval = 10
    private var receiveTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?

    public init(config: Config) {
        self.config = config
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.waitsForConnectivity = true
        self.session = URLSession(configuration: configuration)
    }

    public func connect() {
        isStopped = false
        isReconnecting = false
        receiveTask?.cancel()
        pingTask?.cancel()
        task?.cancel(with: .goingAway, reason: nil)

        guard let url = URL(string: config.url) else {
            config.onStateChange("地址不合法")
            return
        }
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        connectedAt = Date()
        config.onStateChange("连接中")

        receiveTask = Task { [weak self] in
            await self?.receiveLoop(task)
        }
        Task { [weak self] in
            guard let self else { return }
            // 登录与订阅连续发出：各平台都是按顺序处理消息，订阅会排在登录之后
            if let login = self.config.login {
                await self.send(login())
            }
            if let message = self.config.subscribe() {
                await self.send(message)
            }
            if let payload = self.config.pingPayload {
                self.startPing(payload)
            }
        }
    }

    public func stop() {
        isStopped = true
        isReconnecting = false
        receiveTask?.cancel()
        receiveTask = nil
        pingTask?.cancel()
        pingTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    // MARK: - 发送

    /// 发一条消息。订阅变更（新增 / 取消交易对）也用它。
    public func send(_ object: [String: Any]) async {
        guard
            let task,
            let data = try? JSONSerialization.data(withJSONObject: object),
            let text = String(data: data, encoding: .utf8)
        else { return }
        try? await task.send(.string(text))
    }

    private func startPing(_ payload: String) {
        pingTask?.cancel()
        let interval = config.pingInterval
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard let self, !self.isStopped, let task = self.task else { return }
                try? await task.send(.string(payload))
            }
        }
    }

    // MARK: - 接收

    private func receiveLoop(_ task: URLSessionWebSocketTask) async {
        while !isStopped, self.task === task {
            do {
                let message = try await task.receive()
                handle(message)
            } catch {
                guard !isStopped, !isReconnecting, self.task === task else { return }
                isReconnecting = true
                config.onStateChange("已断开：\(error.localizedDescription)")
                scheduleReconnect()
                return
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .string(let text):
            data = Data(text.utf8)
        case .data(let raw):
            data = raw
        @unknown default:
            return
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        config.onMessage(object)
    }

    private func scheduleReconnect() {
        guard !isStopped else { return }
        task?.cancel(with: .goingAway, reason: nil)
        task = nil

        // 上一轮连接稳定过才把退避清零。注意判据不能用「收到过报文」——
        // 凭证错误时服务端也会回一条 auth 失败再断开，那样退避会永远停在 1 秒，
        // 变成每秒重连刷鉴权。
        if let connectedAt, Date().timeIntervalSince(connectedAt) >= Self.stableConnectionDuration {
            retryDelay = 1
        }
        connectedAt = nil

        let delay = retryDelay
        retryDelay = min(retryDelay * 2, 30)
        config.onStateChange("\(Int(delay)) 秒后重连")
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !self.isStopped else { return }
            self.connect()
        }
    }
}

/// 各平台通用的签名工具（HMAC-SHA256）
enum ExchangeSign {
    /// 十六进制小写（币安 / Bybit）
    static func hex(_ message: String, secret: String) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        return mac.map { String(format: "%02x", $0) }.joined()
    }

    /// Base64（OKX）
    static func base64(_ message: String, secret: String) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        return Data(mac).base64EncodedString()
    }
}
