import Foundation
import CryptoKit

/// OKX v5 私有 WebSocket 客户端，只为「合约 / 保证金持仓」提供实时推送。
///
/// 流程：连接 → 登录（HMAC 签名）→ 订阅 `positions` → 持续收推送 → 断线指数退避重连。
/// 每个账户一个连接；收到的持仓增量通过 `onPositions` 回调出去，由 PositionStore 合并进列表。
///
/// 说明：现货余额走的是另一个频道（`account`）、网格策略没有推送频道，
/// 这两类目前仍由 REST 轮询兜底，这里不处理。
@MainActor
public final class OKXWebSocketClient {
    /// 推送来的持仓增量（可能只含发生变化的持仓）
    public var onPositions: (@MainActor ([OKXPositionRaw]) -> Void)?
    /// 连接状态变化，用于展示/排查
    public var onStateChange: (@MainActor (String) -> Void)?

    private let credentials: OKXClient.Credentials
    private let urlString: String
    private let session: URLSession

    private var task: URLSessionWebSocketTask?
    private var isStopped = true
    private var isReconnecting = false
    private var retryDelay: TimeInterval = 1
    private var receiveTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?

    /// 订阅哪些持仓类型；没持仓的类型静默为空
    private static let instTypes = ["SWAP", "FUTURES", "MARGIN", "OPTION"]
    /// 心跳间隔。OKX 要求 30 秒内至少有一次数据/心跳，取 20 秒留余量。
    private static let pingInterval: Duration = .seconds(20)

    public init(credentials: OKXClient.Credentials) {
        self.credentials = credentials
        // 模拟盘走 wspap，正式盘走 ws
        self.urlString = credentials.simulated
            ? "wss://wspap.okx.com:8443/ws/v5/private?brokerId=9999"
            : "wss://ws.okx.com:8443/ws/v5/private"
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

        guard let url = URL(string: urlString) else {
            onStateChange?("地址不合法")
            return
        }
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        onStateChange?("连接中")

        receiveTask = Task { [weak self] in
            await self?.receiveLoop(task)
        }
        Task { [weak self] in
            await self?.sendLogin()
            await self?.schedulePing()
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

    private func send(_ object: [String: Any]) async {
        guard
            let task,
            let data = try? JSONSerialization.data(withJSONObject: object),
            let text = String(data: data, encoding: .utf8)
        else { return }
        do {
            try await task.send(.string(text))
        } catch {
            onStateChange?("发送失败：\(error.localizedDescription)")
        }
    }

    private func sendLogin() async {
        // 登录签名的 message 固定是：时间戳 + "GET" + "/users/self/verify"
        let timestamp = String(format: "%.3f", Date().timeIntervalSince1970)
        let sign = Self.sign(message: timestamp + "GET" + "/users/self/verify", secret: credentials.secretKey)
        await send([
            "op": "login",
            "args": [[
                "apiKey": credentials.apiKey,
                "passphrase": credentials.passphrase,
                "timestamp": timestamp,
                "sign": sign
            ]]
        ])
    }

    private func subscribePositions() async {
        let args: [[String: String]] = Self.instTypes.map { ["channel": "positions", "instType": $0] }
        await send(["op": "subscribe", "args": args])
    }

    private func schedulePing() async {
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pingInterval)
                guard let self, !self.isStopped else { return }
                if let task = self.task {
                    try? await task.send(.string("ping"))
                }
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
                onStateChange?("已断开：\(error.localizedDescription)")
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

        if let event = object["event"] as? String {
            handleEvent(event, object)
            return
        }

        if let raws = OKXPositionPush.decode(data), !raws.isEmpty {
            onPositions?(raws)
        }
    }

    private func handleEvent(_ event: String, _ object: [String: Any]) {
        let code = object["code"] as? String
        let message = object["msg"] as? String ?? ""
        switch event {
        case "login":
            if code == "0" {
                retryDelay = 1
                onStateChange?("已登录")
                Task { [weak self] in await self?.subscribePositions() }
            } else {
                onStateChange?("登录失败 [\(code ?? "-")]：\(message)")
            }
        case "subscribe":
            onStateChange?("已订阅")
        case "error":
            onStateChange?("接口错误 [\(code ?? "-")]：\(message)")
        default:
            break
        }
    }

    private func scheduleReconnect() {
        guard !isStopped else { return }
        task?.cancel(with: .goingAway, reason: nil)
        task = nil

        let delay = retryDelay
        retryDelay = min(retryDelay * 2, 30)
        onStateChange?("\(Int(delay)) 秒后重连")
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !self.isStopped else { return }
            self.connect()
        }
    }

    // MARK: - 解码 / 签名

    private static func sign(message: String, secret: String) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        return Data(mac).base64EncodedString()
    }
}
