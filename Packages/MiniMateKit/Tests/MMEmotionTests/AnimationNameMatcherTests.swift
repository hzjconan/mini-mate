import Testing
@testable import MMAvatar

@Suite("AnimationNameMatcher")
struct AnimationNameMatcherTests {
    @Test func matchesExactActionName() {
        #expect(AnimationNameMatcher.tag(for: "nod") == .nod)
        #expect(AnimationNameMatcher.tag(for: "lookAround") == .lookAround)
    }

    @Test func matchesNameWithSkeletonPrefix() {
        #expect(AnimationNameMatcher.tag(for: "Armature|wave") == .wave)
        #expect(AnimationNameMatcher.tag(for: "Armature|Action|shyCover") == .shyCover)
    }

    @Test func matchesUSDZAnimationPath() {
        #expect(AnimationNameMatcher.tag(for: "/root/Armature/Armature/nod[0]") == .nod)
        #expect(AnimationNameMatcher.tag(for: "/root/Armature/Armature/lookAround") == .lookAround)
    }

    @Test func rejectsUnknownNamesAndSubstrings() {
        #expect(AnimationNameMatcher.tag(for: "nodding") == nil)
        #expect(AnimationNameMatcher.tag(for: "Armature|idleLoop") == nil)
        #expect(AnimationNameMatcher.tag(for: "default subtree animation") == nil)
        #expect(AnimationNameMatcher.tag(for: "") == nil)
    }

    @Test func isCaseSensitive() {
        #expect(AnimationNameMatcher.tag(for: "Nod") == nil)
    }
}
