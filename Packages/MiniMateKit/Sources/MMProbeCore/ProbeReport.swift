import Foundation
import MMCore
import MMConversation

public struct RealtimeTurnResult: Sendable, Equatable {
    public let sampleName: String
    public let groupName: String?
    public let rawText: String
    public let cleanText: String
    public let userEmotion: UserEmotion?
    public let assistantEmotions: [EmotionTag]
    public let actions: [ActionTag]
    public let commands: [AssistantCommand]
    public let userTranscript: String?
    public let firstTextLatencyMs: Double?
    public let unexpectedAudioCount: Int

    public init(
        sampleName: String,
        groupName: String? = nil,
        rawText: String,
        cleanText: String,
        userEmotion: UserEmotion?,
        assistantEmotions: [EmotionTag],
        actions: [ActionTag],
        commands: [AssistantCommand],
        userTranscript: String?,
        firstTextLatencyMs: Double?,
        unexpectedAudioCount: Int
    ) {
        self.sampleName = sampleName
        self.groupName = groupName
        self.rawText = rawText
        self.cleanText = cleanText
        self.userEmotion = userEmotion
        self.assistantEmotions = assistantEmotions
        self.actions = actions
        self.commands = commands
        self.userTranscript = userTranscript
        self.firstTextLatencyMs = firstTextLatencyMs
        self.unexpectedAudioCount = unexpectedAudioCount
    }
}

public struct TTSEmotionResult: Sendable, Equatable {
    public let emotion: EmotionTag
    public let outputPath: String
    public let ttfbMs: Double?
    public let durationSeconds: Double
    public let chunkCount: Int
    public let markCount: Int
}

public enum ProbeReport {
    /// Nearest-rank percentile (e.g. `percentile = 0.50` for p50).
    public static func nearestRankPercentile(_ values: [Double], percentile: Double) -> Double? {
        let sorted = values.filter(\.isFinite).sorted()
        guard !sorted.isEmpty else { return nil }
        let clamped = min(max(percentile, 0), 1)
        let rank = Int(ceil(clamped * Double(sorted.count)))
        let index = max(0, min(sorted.count - 1, rank - 1))
        return sorted[index]
    }

    public static func renderDriversTable(_ descriptors: [ProviderDriverDescriptor]) -> String {
        var lines: [String] = [
            "| Driver ID | Role | Name | Secret Required | Mock | Summary |",
            "| :--- | :--- | :--- | :--- | :--- | :--- |",
        ]
        for d in descriptors {
            lines.append(
                "| `\(d.id)` | `\(d.role.rawValue)` | \(d.displayName) | \(d.requiresPrimarySecret ? "yes" : "no") | \(d.isBuiltInMock ? "yes" : "no") | \(d.summary) |"
            )
        }
        return lines.joined(separator: "\n")
    }

    public static func renderRealtimeReport(driverID: String, result: RealtimeTurnResult) -> String {
        let v4Status = result.unexpectedAudioCount == 0 ? "PASS" : "FAIL (\(result.unexpectedAudioCount) audio events)"
        let latencyText = result.firstTextLatencyMs.map { String(format: "%.1f ms", $0) } ?? "N/A"
        let emotionsText = result.assistantEmotions.map(\.rawValue).joined(separator: ", ")
        let actionsText = result.actions.map(\.rawValue).joined(separator: ", ")
        let commandsText = result.commands.map(\.rawValue).joined(separator: ", ")

        return """
        ### Realtime Probe (`\(driverID)`)
        - **Sample**: `\(result.sampleName)`
        - **V4 Text-Only Audit**: \(v4Status)
        - **V7 User Transcript**: \(result.userTranscript ?? "(none)")
        - **speech_end -> first_text**: \(latencyText)
        - **`<user>`**: \(result.userEmotion?.rawValue ?? "(none)")
        - **`<emo>`**: \(emotionsText.isEmpty ? "(none)" : emotionsText)
        - **`<act>`**: \(actionsText.isEmpty ? "(none)" : actionsText)
        - **`<cmd>`**: \(commandsText.isEmpty ? "(none)" : commandsText)
        - **Clean Text**: \(result.cleanText)
        - **Raw Text**: \(result.rawText)
        """
    }

    public static func renderToneSuiteReport(driverID: String, results: [RealtimeTurnResult]) -> String {
        var lines: [String] = [
            "### Tone Suite Report (`\(driverID)`)",
            "",
            "| Group | Sample | `<user>` | `<emo>` | First Text (ms) | V7 Transcript | V4 Audio | Reply |",
            "| :--- | :--- | :--- | :--- | ---: | :--- | ---: | :--- |",
        ]

        for r in results {
            let latency = r.firstTextLatencyMs.map { String(format: "%.1f", $0) } ?? "N/A"
            let emo = r.assistantEmotions.first?.rawValue ?? "-"
            let transcript = r.userTranscript.map { $0.isEmpty ? "-" : "yes" } ?? "-"
            let reply = r.cleanText.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ")
            lines.append(
                "| \(r.groupName ?? "-") | `\(r.sampleName)` | \(r.userEmotion?.rawValue ?? "-") | \(emo) | \(latency) | \(transcript) | \(r.unexpectedAudioCount) | \(reply) |"
            )
        }

        let totalUnexpectedAudio = results.reduce(0) { $0 + $1.unexpectedAudioCount }
        let v4Summary = totalUnexpectedAudio == 0 ? "PASS (0 audio events)" : "FAIL (\(totalUnexpectedAudio) audio events)"
        let latencies = results.compactMap(\.firstTextLatencyMs)
        let p50Text = nearestRankPercentile(latencies, percentile: 0.50).map { String(format: "%.1f ms", $0) } ?? "N/A"
        let transcriptHits = results.filter { ($0.userTranscript?.isEmpty == false) }.count

        let groups = ["fine", "ok", "done"]
        var distinguishableGroups = 0
        for group in groups {
            let groupResults = results.filter { $0.groupName == group }
            let distinctUserEmotions = Set(groupResults.compactMap(\.userEmotion))
            let distinctReplies = Set(groupResults.map(\.cleanText).filter { !$0.isEmpty })
            if distinctUserEmotions.count >= 2 && distinctReplies.count >= 2 {
                distinguishableGroups += 1
            }
        }

        lines.append("")
        lines.append("#### Summary")
        lines.append("- **V4 Text-Only Audit**: \(v4Summary)")
        lines.append("- **V5 / SC-002 Distinguishable Tone Groups**: \(distinguishableGroups)/3")
        lines.append("- **First Text Latency p50**: \(p50Text)")
        lines.append("- **V7 User Transcript Hits**: \(transcriptHits)/\(results.count)")

        return lines.joined(separator: "\n")
    }

    public static func renderTTSReport(driverID: String, results: [TTSEmotionResult]) -> String {
        var lines: [String] = [
            "### TTS Probe (`\(driverID)`)",
            "",
            "| Emotion | TTFB (ms) | Duration (s) | Chunks | Marks | Output |",
            "| :--- | ---: | ---: | ---: | ---: | :--- |",
        ]
        for r in results {
            let ttfb = r.ttfbMs.map { String(format: "%.1f", $0) } ?? "N/A"
            lines.append(
                String(
                    format: "| `%@` | %@ | %.2f | %d | %d | `%@` |",
                    r.emotion.rawValue,
                    ttfb,
                    r.durationSeconds,
                    r.chunkCount,
                    r.markCount,
                    r.outputPath
                )
            )
        }
        let ttfbs = results.compactMap(\.ttfbMs)
        let p50Text = nearestRankPercentile(ttfbs, percentile: 0.50).map { String(format: "%.1f ms", $0) } ?? "N/A"
        lines.append("")
        lines.append("- **V6 TTFB p50**: \(p50Text)")
        return lines.joined(separator: "\n")
    }
}
