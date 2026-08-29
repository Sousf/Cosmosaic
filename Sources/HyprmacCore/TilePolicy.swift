import CoreGraphics

/// The float-or-tile decision, layered by trustworthiness: explicit user
/// rules first (tile beats float), then structural signals, then the size
/// heuristic. Pure and testable; callers feed it live AX facts.
public enum TilePolicy {

    public enum Verdict: Sendable, Equatable {
        case tile
        case float
    }

    public static func verdict(rules: [WindowRule], appName: String, title: String,
                               isResizable: Bool, size: CGSize,
                               floatBelowSize: CGSize) -> Verdict {
        // Layer 1: explicit user rules; a tile rule beats a float rule.
        let matching = rules.filter { $0.matches(appName: appName, title: title) }
        if matching.contains(where: { $0.effect == .tile }) { return .tile }
        if matching.contains(where: { $0.effect == .float }) { return .float }

        // Layer 2: a window the app won't let us resize cannot fill a tile.
        if !isResizable { return .float }

        // Layer 3: born small in both dimensions → utility panel in practice.
        if floatBelowSize.width > 0, floatBelowSize.height > 0,
           size.width < floatBelowSize.width, size.height < floatBelowSize.height {
            return .float
        }

        return .tile
    }
}

extension WindowRule {
    /// A rule matches if its pattern hits the app name or the window title.
    public func matches(appName: String, title: String) -> Bool {
        appName.range(of: appPattern, options: .regularExpression) != nil
            || title.range(of: appPattern, options: .regularExpression) != nil
    }
}
