# MarketdogCore

供看盘狗 macOS 与 iOS 共同使用的 Swift Package，支持 macOS 14+ 和 iOS 16+。

- `OKXClient`：只读 REST 请求、签名、限流重试。
- `OKXModels`：OKX 响应、持仓、余额与行情模型。
- `OKXPortfolioMapping`：两端共用的合约、现货数量与盈亏字段映射。
- `OKXPortfolioService`：统一拉取并整理合约、交易账户现货、简单赚币活期、链上赚币/质押、策略和全账户总权益快照。
- `OKXMarketData`：行情推送解码、交易对代号与三种涨跌口径。
- `OKXMarketService`：公开行情批量查询、限速分批与涨跌计算。
- `OKXDisplayValues`：两端统一的价格、资产价值及涨跌回退口径，不包含 UI。
- `SpotCostBasis`：两端共用的本地现货移动加权平均成本计算；记录文件仍由各 App 保存。
- `OKXCredentialTransfer`：两端共用的版本化凭证二维码内容校验；Base64 只是编码，不提供加密。
- `PlatformWebSocket`：连接、订阅、心跳和断线重连。
- `OKXPublicTickerStream`：两端共用的公开行情订阅与解析。
- `OKXWebSocketClient`：只读私有 `positions` 推送，供两端更新合约持仓。
- `CoinIconCatalog`：两端共用的币种图标映射与内置 SVG 资源路径。

图标资源来自 [Web3 Icons](https://github.com/0xa3k5/web3icons) 的 `raw-svgs/tokens/branded`，固定上游提交 `ad3cbe05229db54931cd8b2c2a86662288a0ce50`。Core 内置 1,791 个币种 SVG；HYPE 使用同一上游的 `raw-svgs/networks/branded/hyper-evm.svg`（Hyperliquid 网络标志）。原始 SVG 保存在 `Sources/MarketdogCore/Resources/CoinIcons/`，不预先转成位图；各 App 负责渲染并缓存结果。上游 MIT 许可随资源包含在 `WEB3ICONS-LICENSE.txt`，项目标志仍可能涉及各自的商标权。

Core 负责 OKX 读取、解析、归一化和分析；App 只保留 UI、布局、凭证保存位置和平台生命周期。

## OKX 只读接口映射

`OKXPortfolioService` 对应以下 OKX V5 查询接口：

- `/api/v5/account/positions`：合约 / 保证金持仓。
- `/api/v5/account/balance`：交易账户余额。
- `/api/v5/finance/savings/balance`：简单赚币活期余额。
- `/api/v5/finance/staking-defi/orders-active`：链上赚币与质押中的投入资产，支持分页读取。
- `/api/v5/asset/asset-valuation?ccy=USDT`：全账户估值，Core 对该接口做短时缓存以遵守限频。
- `/api/v5/market/tickers?instType=SPOT`：公开现货报价，用于赚币资产的 USDT 折算。

赚币接口单独失败时不会丢弃交易账户或合约数据，快照会通过 `warnings` 把对应接口的读取问题交给 UI 展示。Core 不包含任何下单、划转、申购或赎回调用。

在此目录运行 `swift test` 可验证共享模型和错误判定；两个 App 还需分别构建。
