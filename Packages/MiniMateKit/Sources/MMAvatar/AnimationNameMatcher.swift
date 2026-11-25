import MMCore

/// 把素材里的动画名映射到 `ActionTag`。
///
/// RealityKit 从 USDZ 读出的动画名可能是 `/root/Armature/Armature/nod[0]` 这类路径，
/// DCC 导出时也可能带骨架前缀（`Armature|nod`）。先取最后一段、去掉 `[n]` 下标，
/// 再对 `ActionTag` 做精确匹配，不做子串匹配，避免 `nodding` 之类误命中。
enum AnimationNameMatcher {
    static func leafName(_ animationName: String) -> String {
        var leaf = animationName.split(separator: "|").last.map(String.init) ?? animationName
        leaf = leaf.split(separator: "/").last.map(String.init) ?? leaf
        if let bracket = leaf.firstIndex(of: "[") {
            leaf = String(leaf[..<bracket])
        }
        return leaf
    }

    static func tag(for animationName: String) -> ActionTag? {
        ActionTag(rawValue: leafName(animationName))
    }
}
