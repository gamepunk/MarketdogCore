# MarketdogCore

供看盘狗 macOS 与 iOS 共同使用的 Swift Package，支持 macOS 14+ 和 iOS 16+。

- `OKXClient`：只读 REST 请求、签名、限流重试。
- `OKXModels`：OKX 响应、持仓、余额与行情模型。
- `OKXPortfolioMapping`：两端共用的合约、现货数量与盈亏字段映射。
- `OKXPortfolioService`：统一拉取并整理合约、现货、策略和总权益快照。
- `OKXMarketData`：行情推送解码、交易对代号与三种涨跌口径。
- `OKXMarketService`：公开行情批量查询、限速分批与涨跌计算。
- `OKXDisplayValues`：两端统一的价格、资产价值及涨跌回退口径，不包含 UI。
- `PlatformWebSocket`：连接、订阅、心跳和断线重连。
- `OKXPublicTickerStream`：两端共用的公开行情订阅与解析。
- `OKXWebSocketClient`：只读私有 `positions` 推送，供两端更新合约持仓。

Core 负责 OKX 读取、解析、归一化和分析；App 只保留 UI、布局、凭证保存位置和平台生命周期。

在此目录运行 `swift test` 可验证共享模型和错误判定；两个 App 还需分别构建。
