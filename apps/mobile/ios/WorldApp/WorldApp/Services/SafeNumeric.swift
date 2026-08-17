import Foundation
import CoreGraphics

/// Crash guards: Swift traps on `Int(Double.nan)` / `Int(.infinity)`.
enum SafeNumeric {
    /// Finite seconds suitable for UI / persistence (never NaN/Inf).
    static func seconds(_ value: Double, fallback: Double = 0) -> Double {
        guard value.isFinite, !value.isNaN else { return fallback }
        return value
    }

    /// Non-negative finite seconds.
    static func nonNegativeSeconds(_ value: Double) -> Double {
        max(0, seconds(value))
    }

    /// Safe `Int` from a Double — never traps on NaN/Inf/overflow.
    static func int(_ value: Double, fallback: Int = 0, min minV: Int = Int.min, max maxV: Int = Int.max) -> Int {
        guard value.isFinite, !value.isNaN else { return fallback }
        let r = value.rounded(.down)
        guard r.isFinite, !r.isNaN else { return fallback }
        if r >= Double(maxV) { return maxV }
        if r <= Double(minV) { return minV }
        return Int(r)
    }

    static func cgFloat(_ value: CGFloat, fallback: CGFloat = 0) -> CGFloat {
        guard value.isFinite, !value.isNaN else { return fallback }
        return value
    }

    static func positiveCGFloat(_ value: CGFloat, fallback: CGFloat = 1) -> CGFloat {
        let v = cgFloat(value, fallback: fallback)
        return v > 0 ? v : fallback
    }
}
