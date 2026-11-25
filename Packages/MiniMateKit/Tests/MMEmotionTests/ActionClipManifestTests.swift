import Foundation
import Testing
@testable import MMAvatar

@Suite("ActionClipManifest")
struct ActionClipManifestTests {
    private func decode(_ json: String) throws -> [ActionClipManifest.TimelineClip] {
        try ActionClipManifest.decode(Data(json.utf8)).timelineClips()
    }

    @Test func mapsFramesToSeconds() throws {
        let clips = try decode(
            """
            {
              "version": 1,
              "fps": 30,
              "animation": "actions",
              "totalFrames": 76,
              "clips": {
                "nod": {"startFrame": 1, "endFrame": 31},
                "wave": {"startFrame": 34, "endFrame": 76}
              }
            }
            """
        )

        #expect(clips.count == 2)
        let nod = try #require(clips.first { $0.tag == .nod })
        #expect(abs(nod.start - 0.0) < 1e-9)
        #expect(abs(nod.duration - 1.0) < 1e-9)

        let wave = try #require(clips.first { $0.tag == .wave })
        #expect(abs(wave.start - 33.0 / 30.0) < 1e-9)
        #expect(abs(wave.duration - 42.0 / 30.0) < 1e-9)
    }

    @Test func returnsClipsInActionTagOrder() throws {
        let clips = try decode(
            """
            {
              "version": 1,
              "fps": 30,
              "clips": {
                "notice": {"startFrame": 10, "endFrame": 20},
                "nod": {"startFrame": 1, "endFrame": 5}
              }
            }
            """
        )

        #expect(clips.map(\.tag) == [.nod, .notice])
    }

    @Test func ignoresUnknownTags() throws {
        let clips = try decode(
            """
            {
              "version": 1,
              "fps": 30,
              "clips": {
                "nod": {"startFrame": 1, "endFrame": 5},
                "dance": {"startFrame": 6, "endFrame": 9}
              }
            }
            """
        )

        #expect(clips.map(\.tag) == [.nod])
    }

    @Test func rejectsUnsupportedVersion() {
        #expect(throws: ActionClipManifestError.unsupportedVersion(2)) {
            try decode("""
            {"version": 2, "fps": 30, "clips": {"nod": {"startFrame": 1, "endFrame": 5}}}
            """)
        }
    }

    @Test(arguments: [0.0, -30.0])
    func rejectsInvalidFPS(_ fps: Double) {
        #expect(throws: ActionClipManifestError.invalidFPS(fps)) {
            try decode("""
            {"version": 1, "fps": \(fps), "clips": {"nod": {"startFrame": 1, "endFrame": 5}}}
            """)
        }
    }

    @Test func rejectsInvalidFrameRanges() {
        #expect(throws: ActionClipManifestError.invalidClip("nod")) {
            try decode("""
            {"version": 1, "fps": 30, "clips": {"nod": {"startFrame": 5, "endFrame": 5}}}
            """)
        }
        #expect(throws: ActionClipManifestError.invalidClip("nod")) {
            try decode("""
            {"version": 1, "fps": 30, "clips": {"nod": {"startFrame": 0, "endFrame": 5}}}
            """)
        }
        #expect(throws: ActionClipManifestError.invalidClip("nod")) {
            try decode("""
            {"version": 1, "fps": 30, "totalFrames": 10, "clips": {"nod": {"startFrame": 1, "endFrame": 11}}}
            """)
        }
    }
}
