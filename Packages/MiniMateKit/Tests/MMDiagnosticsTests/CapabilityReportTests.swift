import Foundation
import Testing
@testable import MMDiagnostics

@Suite("CapabilityReport.markdown()")
struct CapabilityReportTests {
    private func makeReport(results: [CapabilityResult]) -> CapabilityReport {
        CapabilityReport(
            deviceModel: "iPhone17,2",
            systemVersion: "26.1",
            createdAt: Date(timeIntervalSince1970: 1_763_600_000),
            results: results
        )
    }

    @Test func headerContainsDeviceInfoAndTableHeader() {
        let markdown = makeReport(results: []).markdown()

        #expect(markdown.contains("iPhone17,2"))
        #expect(markdown.contains("26.1"))
        #expect(markdown.contains("| 项 | 结果 | 原因 | 耗时 |"))
    }

    @Test func rowsFollowDeclaredCapabilityIDOrder() {
        let shuffled = CapabilityID.allCases.reversed().map {
            CapabilityResult(id: $0, status: .available, detail: nil, duration: .milliseconds(100))
        }
        let markdown = makeReport(results: shuffled).markdown()

        var lastIndex = markdown.startIndex
        for capability in CapabilityID.allCases {
            guard let range = markdown.range(of: "| \(capability.title) |") else {
                Issue.record("missing row for \(capability)")
                return
            }
            #expect(range.lowerBound >= lastIndex, "\(capability) out of order")
            lastIndex = range.lowerBound
        }
    }

    @Test func statusRendersChineseLabelsAndReasons() {
        let results = [
            CapabilityResult(id: .foundationModels, status: .available, detail: "zh 已安装", duration: .zero),
            CapabilityResult(id: .speechDetector, status: .unavailable(reason: "Apple Intelligence 未开启"), detail: nil, duration: .zero),
            CapabilityResult(id: .arFaceTracking, status: .error(message: "boom"), detail: nil, duration: .zero),
        ]
        let markdown = makeReport(results: results).markdown()

        #expect(markdown.contains("可用"))
        #expect(markdown.contains("不可用"))
        #expect(markdown.contains("出错"))
        #expect(markdown.contains("Apple Intelligence 未开启"))
        #expect(markdown.contains("boom"))
        #expect(markdown.contains("zh 已安装"))
    }

    @Test func pipeCharactersInReasonAreEscaped() {
        let result = CapabilityResult(
            id: .nlEmbeddingChinese,
            status: .unavailable(reason: "a|b"),
            detail: nil,
            duration: .zero
        )
        let markdown = makeReport(results: [result]).markdown()

        #expect(markdown.contains("a\\|b"))
        #expect(!markdown.contains("a|b"))
    }

    @Test func newlinesInDetailDoNotBreakTable() {
        let result = CapabilityResult(
            id: .speechTranscriberChinese,
            status: .available,
            detail: "line1\nline2",
            duration: .zero
        )
        let markdown = makeReport(results: [result]).markdown()

        #expect(markdown.contains("line1 line2"))
        #expect(!markdown.contains("line1\nline2"))
    }
}
