import Testing
@testable import MMDiagnostics

@Suite("EmbeddingSmokeTest")
struct EmbeddingSmokeTestTests {
    private let triples = [
        EmbeddingSmokeTest.Triple(anchor: "a", near: "a1", far: "a2"),
        EmbeddingSmokeTest.Triple(anchor: "b", near: "b1", far: "b2"),
    ]

    private func distance(_ table: [String: Double]) -> (String, String) -> Double {
        { table[$0 + "|" + $1] ?? .nan }
    }

    @Test func allOrderedTriplesAreCounted() {
        let outcome = EmbeddingSmokeTest.run(
            triples,
            distance: distance(["a|a1": 0.1, "a|a2": 0.5, "b|b1": 0.2, "b|b2": 0.3])
        )

        #expect(outcome.ordered == 2)
        #expect(outcome.total == 2)
        #expect(outcome.detail == "近<远 2/2：0.100<0.500，0.200<0.300")
    }

    @Test func reversedTripleIsMarked() {
        let outcome = EmbeddingSmokeTest.run(
            triples,
            distance: distance(["a|a1": 0.1, "a|a2": 0.5, "b|b1": 0.469, "b|b2": 0.401])
        )

        #expect(outcome.ordered == 1)
        #expect(outcome.detail == "近<远 1/2：0.100<0.500，0.469>0.401")
    }

    @Test func equalDistancesAreNotOrdered() {
        let outcome = EmbeddingSmokeTest.run(
            triples,
            distance: distance(["a|a1": 0.3, "a|a2": 0.3, "b|b1": 0.1, "b|b2": 0.2])
        )

        #expect(outcome.ordered == 1)
        #expect(outcome.detail.contains("0.300=0.300"))
    }

    @Test func throwingDistancePropagates() {
        struct Boom: Error {}
        #expect(throws: Boom.self) {
            try EmbeddingSmokeTest.run(triples) { _, _ in throw Boom() }
        }
    }

    @Test func defaultTriplesCoverSeveralIntents() {
        #expect(EmbeddingSmokeTest.defaultTriples.count >= 3)
    }
}
