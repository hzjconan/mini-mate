import Testing
import MMAvatar

@Suite("BlendShapeIndex")
struct BlendShapeIndexTests {
    @Test func arkitNameListCoversAllFiftyTwoShapes() {
        #expect(BlendShapeIndex.arkitNames.count == 52)
        #expect(Set(BlendShapeIndex.arkitNames).count == 52)
    }

    @Test func mapsNamesToTheirPositionInTheModel() {
        let modelNames = Array(BlendShapeIndex.arkitNames.reversed())
        let index = BlendShapeIndex(availableNames: modelNames)

        #expect(index.missingNames.isEmpty)
        #expect(index.index(for: "browInnerUp") == modelNames.firstIndex(of: "browInnerUp"))
        #expect(index.index(for: "jawOpen") == modelNames.firstIndex(of: "jawOpen"))
        #expect(index.index(for: "tongueOut") == modelNames.firstIndex(of: "tongueOut"))
    }

    @Test func reportsMissingArkitNamesInArkitOrder() {
        let modelNames = BlendShapeIndex.arkitNames.filter { $0 != "jawOpen" && $0 != "eyeBlinkLeft" }
        let index = BlendShapeIndex(availableNames: modelNames)

        #expect(index.missingNames == ["eyeBlinkLeft", "jawOpen"])
        #expect(index.index(for: "jawOpen") == nil)
        #expect(index.index(for: "eyeBlinkLeft") == nil)
    }

    @Test func ignoresModelNamesOutsideArkitSet() {
        let modelNames = BlendShapeIndex.arkitNames + ["customExtra"]
        let index = BlendShapeIndex(availableNames: modelNames)

        #expect(index.missingNames.isEmpty)
        #expect(index.index(for: "customExtra") == nil)
    }

    @Test func duplicateModelNamesKeepFirstOccurrence() {
        let modelNames = ["jawOpen"] + BlendShapeIndex.arkitNames
        let index = BlendShapeIndex(availableNames: modelNames)

        #expect(index.index(for: "jawOpen") == 0)
    }
}
