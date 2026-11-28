import Foundation
import MMAudio
import MMCore
import MMConversation
import MMSecurity

public struct ProbeExecutionResult: Sendable, Equatable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String = "", stderr: String = "") {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

/// Plugin-driven CLI runner for `mm-probe`. Zero hardcoded vendor names.
public struct ProbeRunner: Sendable {
    public static let toneSuiteSamples: [(group: String, fileName: String)] = [
        ("fine", "fine-happy.wav"),
        ("fine", "fine-flat.wav"),
        ("fine", "fine-sad.wav"),
        ("ok", "ok-happy.wav"),
        ("ok", "ok-flat.wav"),
        ("ok", "ok-sad.wav"),
        ("done", "done-happy.wav"),
        ("done", "done-tired.wav"),
        ("done", "done-angry.wav"),
    ]

    private let registry: ProviderRegistry
    private let clock: any MMCore.Clock

    public init(
        registry: ProviderRegistry = .makeDefault(),
        clock: any MMCore.Clock = SystemClock()
    ) {
        self.registry = registry
        self.clock = clock
    }

    public func run(
        arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async -> ProbeExecutionResult {
        let command: ProbeCommand
        do {
            command = try ProbeArguments.parse(arguments)
        } catch {
            return ProbeExecutionResult(exitCode: 2, stderr: "\(error)\n")
        }

        switch command {
        case .help:
            return ProbeExecutionResult(exitCode: 0, stdout: ProbeArguments.usageText + "\n")
        case .listDrivers(let role):
            let descriptors = role.map { registry.descriptors(for: $0) } ?? registry.allDescriptors()
            return ProbeExecutionResult(exitCode: 0, stdout: ProbeReport.renderDriversTable(descriptors) + "\n")
        case .realtime(let options):
            return await runRealtime(options, environment: environment)
        case .toneSuite(let options):
            return await runToneSuite(options, environment: environment)
        case .tts(let options):
            return await runTTS(options, environment: environment)
        case .recordFixture(let options):
            return await runRecordFixture(options, environment: environment)
        }
    }

    // MARK: - Subcommands

    private func runRealtime(
        _ options: RealtimeProbeOptions,
        environment: [String: String]
    ) async -> ProbeExecutionResult {
        guard let descriptor = registry.descriptor(id: options.driverID), descriptor.role == .realtimeBrain else {
            return ProbeExecutionResult(
                exitCode: 2,
                stderr: "Unknown realtime driver '\(options.driverID)'. Run `mm-probe list-drivers --role realtime`.\n"
            )
        }

        let resolvedCreds: ProviderCredentials?
        let secrets: [String]
        do {
            (resolvedCreds, secrets) = try resolveCredentials(
                descriptor: descriptor,
                keyEnv: options.keyEnv,
                secondaryEnv: options.secondaryEnv,
                environment: environment
            )
        } catch let err as MissingEnvError {
            return ProbeExecutionResult(exitCode: 2, stderr: "\(err.message)\n")
        } catch {
            return ProbeExecutionResult(exitCode: 2, stderr: "\(error)\n")
        }

        let inputURL = URL(fileURLWithPath: options.inputPath)
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            return ProbeExecutionResult(exitCode: 2, stderr: "Input audio file not found: \(options.inputPath)\n")
        }

        let validatedProfile: ProviderProfile
        do {
            validatedProfile = try ProviderProfile(
                role: .realtimeBrain,
                name: "probe-\(options.driverID)",
                driverID: options.driverID,
                customEndpoint: options.endpoint,
                modelName: options.model
            ).validatedAndNormalized()
        } catch {
            return ProbeExecutionResult(exitCode: 2, stderr: "Invalid probe configuration: \(error)\n")
        }

        do {
            let turn = try await executeRealtimeTurn(
                profile: validatedProfile,
                sampleURL: inputURL,
                groupName: nil,
                credentials: resolvedCreds,
                chunkMs: options.chunkMs,
                silenceMs: options.silenceMs,
                pace: options.pace,
                timeoutSeconds: options.timeoutSeconds,
                transportOverride: nil
            )
            let report = ProbeReport.renderRealtimeReport(driverID: options.driverID, result: turn)
            return ProbeExecutionResult(exitCode: 0, stdout: report + "\n")
        } catch {
            return ProbeExecutionResult(
                exitCode: 1,
                stderr: SecretRedactor.sanitizedErrorMessage(error, secrets: secrets) + "\n"
            )
        }
    }

    private func runToneSuite(
        _ options: ToneSuiteOptions,
        environment: [String: String]
    ) async -> ProbeExecutionResult {
        guard let descriptor = registry.descriptor(id: options.driverID), descriptor.role == .realtimeBrain else {
            return ProbeExecutionResult(
                exitCode: 2,
                stderr: "Unknown realtime driver '\(options.driverID)'. Run `mm-probe list-drivers --role realtime`.\n"
            )
        }

        let resolvedCreds: ProviderCredentials?
        let secrets: [String]
        do {
            (resolvedCreds, secrets) = try resolveCredentials(
                descriptor: descriptor,
                keyEnv: options.keyEnv,
                secondaryEnv: options.secondaryEnv,
                environment: environment
            )
        } catch let err as MissingEnvError {
            return ProbeExecutionResult(exitCode: 2, stderr: "\(err.message)\n")
        } catch {
            return ProbeExecutionResult(exitCode: 2, stderr: "\(error)\n")
        }

        let samplesDirURL = resolveSamplesDirectory(explicit: options.samplesDir)
        var present: [(group: String, url: URL)] = []
        var missing: [String] = []
        for entry in Self.toneSuiteSamples {
            let url = samplesDirURL.appendingPathComponent(entry.fileName)
            if FileManager.default.fileExists(atPath: url.path) {
                present.append((entry.group, url))
            } else {
                missing.append(url.path)
            }
        }

        if !missing.isEmpty && !options.allowPartial {
            let listing = missing.joined(separator: "\n  - ")
            return ProbeExecutionResult(
                exitCode: 2,
                stderr: "Missing required voice sample(s) (pass --allow-partial to skip missing):\n  - \(listing)\n"
            )
        }
        guard !present.isEmpty else {
            return ProbeExecutionResult(
                exitCode: 2,
                stderr: "No voice samples found in \(samplesDirURL.path).\n"
            )
        }

        let validatedProfile: ProviderProfile
        do {
            validatedProfile = try ProviderProfile(
                role: .realtimeBrain,
                name: "probe-\(options.driverID)",
                driverID: options.driverID,
                customEndpoint: options.endpoint,
                modelName: options.model
            ).validatedAndNormalized()
        } catch {
            return ProbeExecutionResult(exitCode: 2, stderr: "Invalid probe configuration: \(error)\n")
        }

        var results: [RealtimeTurnResult] = []
        do {
            for item in present {
                let turn = try await executeRealtimeTurn(
                    profile: validatedProfile,
                    sampleURL: item.url,
                    groupName: item.group,
                    credentials: resolvedCreds,
                    chunkMs: options.chunkMs,
                    silenceMs: options.silenceMs,
                    pace: options.pace,
                    timeoutSeconds: options.timeoutSeconds,
                    transportOverride: nil
                )
                results.append(turn)
            }
            let report = ProbeReport.renderToneSuiteReport(driverID: options.driverID, results: results)
            return ProbeExecutionResult(exitCode: 0, stdout: report + "\n")
        } catch {
            return ProbeExecutionResult(
                exitCode: 1,
                stderr: SecretRedactor.sanitizedErrorMessage(error, secrets: secrets) + "\n"
            )
        }
    }

    private func runTTS(
        _ options: TTSProbeOptions,
        environment: [String: String]
    ) async -> ProbeExecutionResult {
        guard let descriptor = registry.descriptor(id: options.driverID), descriptor.role == .emotionalTTS else {
            return ProbeExecutionResult(
                exitCode: 2,
                stderr: "Unknown TTS driver '\(options.driverID)'. Run `mm-probe list-drivers --role tts`.\n"
            )
        }

        let resolvedCreds: ProviderCredentials?
        let secrets: [String]
        do {
            (resolvedCreds, secrets) = try resolveCredentials(
                descriptor: descriptor,
                keyEnv: options.keyEnv,
                secondaryEnv: options.secondaryEnv,
                environment: environment
            )
        } catch let err as MissingEnvError {
            return ProbeExecutionResult(exitCode: 2, stderr: "\(err.message)\n")
        } catch {
            return ProbeExecutionResult(exitCode: 2, stderr: "\(error)\n")
        }

        let mappingOverride: TTSEmotionMapping?
        if let mappingPath = options.mappingPath {
            let mappingURL = URL(fileURLWithPath: mappingPath)
            guard FileManager.default.fileExists(atPath: mappingURL.path) else {
                return ProbeExecutionResult(exitCode: 2, stderr: "Mapping file not found: \(mappingPath)\n")
            }
            do {
                mappingOverride = try TTSEmotionMapping.load(fromFile: mappingURL)
            } catch {
                return ProbeExecutionResult(
                    exitCode: 2,
                    stderr: "Invalid mapping JSON at \(mappingPath): \(error)\n"
                )
            }
        } else {
            mappingOverride = nil
        }

        let profile: ProviderProfile
        do {
            profile = try ProviderProfile(
                role: .emotionalTTS,
                name: "probe-\(options.driverID)",
                driverID: options.driverID,
                customEndpoint: options.endpoint,
                modelName: options.model,
                voiceID: options.voice
            ).validatedAndNormalized()
        } catch {
            return ProbeExecutionResult(exitCode: 2, stderr: "Invalid probe configuration: \(error)\n")
        }
        let context = DriverBuildContext(
            clock: clock,
            emotionMappingOverride: mappingOverride
        )

        do {
            let provider = try registry.makeTTSProvider(
                profile: profile,
                credentials: resolvedCreds,
                context: context
            )
            let outDir = URL(fileURLWithPath: options.outputDir, isDirectory: true)
            try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

            var results: [TTSEmotionResult] = []
            for emotion in options.emotions {
                let start = clock.now
                var firstChunkMs: Double?
                var chunks: [AudioChunk] = []
                var markCount = 0

                let stream = provider.synthesize(options.text, emotion: emotion)
                for try await chunk in stream {
                    if firstChunkMs == nil {
                        firstChunkMs = clock.now.timeIntervalSince(start) * 1000.0
                    }
                    chunks.append(chunk)
                    markCount += chunk.marks.count
                }

                let outputFile = outDir.appendingPathComponent("\(emotion.rawValue).wav")
                try WAVCodec.writeWAV(
                    chunks: chunks,
                    sampleRate: provider.outputFormat.sampleRate,
                    to: outputFile
                )
                let duration = chunks.reduce(0.0) { $0 + $1.duration }
                results.append(TTSEmotionResult(
                    emotion: emotion,
                    outputPath: outputFile.path,
                    ttfbMs: firstChunkMs,
                    durationSeconds: duration,
                    chunkCount: chunks.count,
                    markCount: markCount
                ))
            }

            let report = ProbeReport.renderTTSReport(driverID: options.driverID, results: results)
            return ProbeExecutionResult(exitCode: 0, stdout: report + "\n")
        } catch {
            return ProbeExecutionResult(
                exitCode: 1,
                stderr: SecretRedactor.sanitizedErrorMessage(error, secrets: secrets) + "\n"
            )
        }
    }

    private func runRecordFixture(
        _ options: RecordFixtureOptions,
        environment: [String: String]
    ) async -> ProbeExecutionResult {
        guard let descriptor = registry.descriptor(id: options.driverID), descriptor.role == .realtimeBrain else {
            return ProbeExecutionResult(
                exitCode: 2,
                stderr: "Unknown realtime driver '\(options.driverID)'. Run `mm-probe list-drivers --role realtime`.\n"
            )
        }

        let resolvedCreds: ProviderCredentials?
        let secrets: [String]
        do {
            (resolvedCreds, secrets) = try resolveCredentials(
                descriptor: descriptor,
                keyEnv: options.keyEnv,
                secondaryEnv: options.secondaryEnv,
                environment: environment
            )
        } catch let err as MissingEnvError {
            return ProbeExecutionResult(exitCode: 2, stderr: "\(err.message)\n")
        } catch {
            return ProbeExecutionResult(exitCode: 2, stderr: "\(error)\n")
        }

        let inputURL = URL(fileURLWithPath: options.inputPath)
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            return ProbeExecutionResult(exitCode: 2, stderr: "Input audio file not found: \(options.inputPath)\n")
        }

        let validatedProfile: ProviderProfile
        do {
            validatedProfile = try ProviderProfile(
                role: .realtimeBrain,
                name: "probe-\(options.driverID)",
                driverID: options.driverID,
                customEndpoint: options.endpoint,
                modelName: options.model
            ).validatedAndNormalized()
        } catch {
            return ProbeExecutionResult(exitCode: 2, stderr: "Invalid probe configuration: \(error)\n")
        }

        let baseTransport: any WebSocketTransport = descriptor.isBuiltInMock
            ? LoopbackMockWebSocketTransport()
            : URLSessionWebSocketTransport()
        let recorder = RecordingWebSocketTransport(
            underlying: baseTransport,
            secrets: secrets,
            clock: clock
        )

        do {
            let turn = try await executeRealtimeTurn(
                profile: validatedProfile,
                sampleURL: inputURL,
                groupName: nil,
                credentials: resolvedCreds,
                chunkMs: options.chunkMs,
                silenceMs: options.silenceMs,
                pace: options.pace,
                timeoutSeconds: options.timeoutSeconds,
                transportOverride: recorder
            )
            let jsonl = try recorder.encodeJSONLines()
            let outputURL = URL(fileURLWithPath: options.outputPath)
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try jsonl.write(to: outputURL, options: .atomic)
            return ProbeExecutionResult(
                exitCode: 0,
                stdout: "Recorded \(recorder.records.count) sanitized frame(s) to \(outputURL.path) (V4 audio events: \(turn.unexpectedAudioCount)).\n"
            )
        } catch {
            return ProbeExecutionResult(
                exitCode: 1,
                stderr: SecretRedactor.sanitizedErrorMessage(error, secrets: secrets) + "\n"
            )
        }
    }

    // MARK: - Helpers

    private struct MissingEnvError: Error {
        let message: String
    }

    private func resolveCredentials(
        descriptor: ProviderDriverDescriptor,
        keyEnv: String,
        secondaryEnv: String?,
        environment: [String: String]
    ) throws -> (ProviderCredentials?, [String]) {
        let primary = environment[keyEnv]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let secondary = secondaryEnv.flatMap { environment[$0]?.trimmingCharacters(in: .whitespacesAndNewlines) }

        if descriptor.requiresPrimarySecret {
            guard let primary, !primary.isEmpty else {
                throw MissingEnvError(
                    message: "Missing required credential environment variable '\(keyEnv)' for driver '\(descriptor.id)'."
                )
            }
        }

        guard let primary, !primary.isEmpty else {
            return (nil, [])
        }
        let nonEmptySecondary = (secondary?.isEmpty == false) ? secondary : nil
        var secrets = [primary]
        if let nonEmptySecondary {
            secrets.append(nonEmptySecondary)
        }
        return (ProviderCredentials(primarySecret: primary, secondarySecret: nonEmptySecondary), secrets)
    }

    private func resolveSamplesDirectory(explicit: String?) -> URL {
        if let explicit {
            return URL(fileURLWithPath: explicit, isDirectory: true)
        }
        let candidates = [
            URL(fileURLWithPath: "../../Assets/voice-samples", isDirectory: true),
            URL(fileURLWithPath: "Assets/voice-samples", isDirectory: true),
        ]
        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        return candidates[0]
    }

    private func executeRealtimeTurn(
        profile: ProviderProfile,
        sampleURL: URL,
        groupName: String?,
        credentials: ProviderCredentials?,
        chunkMs: Int,
        silenceMs: Int,
        pace: Double,
        timeoutSeconds: Double,
        transportOverride: (any WebSocketTransport)?
    ) async throws -> RealtimeTurnResult {
        let audio = try WAVCodec.loadAudioFile(at: sampleURL, targetSampleRate: 16_000)
        let instructions = try Persona.loadBundled().makeInstructions()

        let context = DriverBuildContext(
            clock: clock,
            webSocketTransport: transportOverride ?? URLSessionWebSocketTransport()
        )
        let session = try registry.makeRealtimeSession(
            profile: profile,
            credentials: credentials,
            context: context
        )

        try await session.connect(instructions: instructions)
        defer {
            Task { await session.close() }
        }

        let collector = Task<TurnCollection, Error> {
            var parser = TagParser()
            var rawText = ""
            var cleanText = ""
            var userEmotion: UserEmotion?
            var emotions: [EmotionTag] = []
            var actions: [ActionTag] = []
            var commands: [AssistantCommand] = []
            var transcript: String?
            var speechEndedAt: Date?
            var firstTextAt: Date?

            for try await event in session.output {
                switch event {
                case .speechStarted:
                    break
                case .speechEnded:
                    speechEndedAt = clock.now
                case .userTranscript(let text, let isFinal):
                    if isFinal || transcript == nil {
                        transcript = text
                    }
                case .textDelta(let delta):
                    if firstTextAt == nil {
                        firstTextAt = clock.now
                    }
                    rawText += delta
                    let segments = parser.feed(delta)
                    Self.apply(segments, cleanText: &cleanText, userEmotion: &userEmotion, emotions: &emotions, actions: &actions, commands: &commands)
                case .responseDone:
                    let trailing = parser.finish()
                    Self.apply(trailing, cleanText: &cleanText, userEmotion: &userEmotion, emotions: &emotions, actions: &actions, commands: &commands)
                    let latencyMs: Double? = {
                        guard let end = speechEndedAt, let first = firstTextAt else { return nil }
                        return max(0, first.timeIntervalSince(end) * 1000.0)
                    }()
                    return TurnCollection(
                        rawText: rawText,
                        cleanText: cleanText,
                        userEmotion: userEmotion,
                        emotions: emotions,
                        actions: actions,
                        commands: commands,
                        transcript: transcript,
                        firstTextLatencyMs: latencyMs
                    )
                case .error(let err):
                    throw err
                }
            }

            if Task.isCancelled {
                throw RealtimeError.network(underlying: "Timed out waiting for realtime response")
            }

            let trailing = parser.finish()
            Self.apply(trailing, cleanText: &cleanText, userEmotion: &userEmotion, emotions: &emotions, actions: &actions, commands: &commands)
            return TurnCollection(
                rawText: rawText,
                cleanText: cleanText,
                userEmotion: userEmotion,
                emotions: emotions,
                actions: actions,
                commands: commands,
                transcript: transcript,
                firstTextLatencyMs: nil
            )
        }

        defer { collector.cancel() }

        // Stream resampled audio in chunks followed by trailing silence so server VAD triggers reliably.
        let samplesPerChunk = max(1, (16_000 * chunkMs) / 1000)
        var offset = 0
        while offset < audio.samples.count {
            let end = min(audio.samples.count, offset + samplesPerChunk)
            let slice = Array(audio.samples[offset..<end])
            try await session.send(AudioChunk(samples: slice, sampleRate: 16_000))
            offset = end
            if pace > 0 {
                let delayMs = Double(chunkMs) / pace
                try await clock.sleep(for: .milliseconds(Int(delayMs.rounded())))
            }
        }

        let silenceSampleCount = (16_000 * silenceMs) / 1000
        var silenceRemaining = silenceSampleCount
        while silenceRemaining > 0 {
            let count = min(samplesPerChunk, silenceRemaining)
            try await session.send(AudioChunk(samples: [Int16](repeating: 0, count: count), sampleRate: 16_000))
            silenceRemaining -= count
            if pace > 0 {
                let delayMs = Double(chunkMs) / pace
                try await clock.sleep(for: .milliseconds(Int(delayMs.rounded())))
            }
        }

        let timeoutTask = Task {
            try await clock.sleep(for: .seconds(timeoutSeconds))
            collector.cancel()
        }
        defer { timeoutTask.cancel() }

        let collected = try await collector.value
        let unexpectedAudio = (session as? any RealtimeSessionAuditable)?.unexpectedAudioEventCount ?? 0
        await session.close()

        return RealtimeTurnResult(
            sampleName: sampleURL.lastPathComponent,
            groupName: groupName,
            rawText: collected.rawText,
            cleanText: collected.cleanText,
            userEmotion: collected.userEmotion,
            assistantEmotions: collected.emotions,
            actions: collected.actions,
            commands: collected.commands,
            userTranscript: collected.transcript,
            firstTextLatencyMs: collected.firstTextLatencyMs,
            unexpectedAudioCount: unexpectedAudio
        )
    }

    private struct TurnCollection: Sendable {
        let rawText: String
        let cleanText: String
        let userEmotion: UserEmotion?
        let emotions: [EmotionTag]
        let actions: [ActionTag]
        let commands: [AssistantCommand]
        let transcript: String?
        let firstTextLatencyMs: Double?
    }

    private static func apply(
        _ segments: [TaggedSegment],
        cleanText: inout String,
        userEmotion: inout UserEmotion?,
        emotions: inout [EmotionTag],
        actions: inout [ActionTag],
        commands: inout [AssistantCommand]
    ) {
        for segment in segments {
            switch segment {
            case .userEmotion(let u):
                if userEmotion == nil { userEmotion = u }
            case .emotion(let e):
                emotions.append(e)
            case .action(let a):
                actions.append(a)
            case .command(let c):
                commands.append(c)
            case .text(let t):
                cleanText += t
            }
        }
    }
}
