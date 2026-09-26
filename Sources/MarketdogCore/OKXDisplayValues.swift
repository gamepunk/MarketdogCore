import Foundation

/// 两端一致的资产数值口径；字符串、颜色和布局仍由各 App 决定。
public enum OKXDisplayValues {
    public enum AssetKind: Sendable {
        case contract
        case spot
        case strategy
    }

    /// 合约优先实时成交价，再退到标记价/快照成交价；现货与策略显示持仓价值。
    public static func primaryNumber(
        kind: AssetKind,
        livePrice: Double?,
        markPrice: Double?,
        lastPrice: Double?,
        valueUSD: Double?
    ) -> Double? {
        switch kind {
        case .contract: livePrice ?? markPrice ?? lastPrice ?? valueUSD
        case .spot, .strategy: valueUSD
        }
    }

    /// 有持仓收益率时显示它，否则回退到行情的滚动 24 小时涨跌。
    public static func changeRatio(positionRatio: Double?, rolling24hRatio: Double?) -> Double? {
        positionRatio ?? rolling24hRatio
    }
}
