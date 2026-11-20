import MMDiagnostics
import SwiftUI

struct DiagnosticsView: View {
    @Environment(AppComposition.self) private var composition

    @State private var results: [CapabilityResult] = []
    @State private var report: CapabilityReport?
    @State private var isRunning = false

    var body: some View {
        List {
            Section {
                Button {
                    run()
                } label: {
                    HStack {
                        Text(isRunning ? "探测中…" : "开始探测")
                        if isRunning {
                            ProgressView()
                                .padding(.leading, 8)
                        }
                    }
                }
                .disabled(isRunning)
            }
            if !results.isEmpty {
                Section("结果") {
                    ForEach(results) { result in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(result.id.title)
                                Spacer()
                                Text(result.status.label)
                                    .foregroundStyle(color(for: result.status))
                            }
                            if let reason = result.status.reason ?? result.detail {
                                Text(reason)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("能力探测")
        .toolbar {
            if let report {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: report.markdown()) {
                        Label("导出", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    private func run() {
        isRunning = true
        results = []
        report = nil
        Task {
            let runner = DiagnosticsRunner(
                probes: DiagnosticsProbes.makeAll(),
                clock: composition.clock
            )
            let outcome = await runner.run()
            let device = DeviceInfo.current
            results = outcome
            report = CapabilityReport(
                deviceModel: device.model,
                systemVersion: device.systemVersion,
                createdAt: Date(),
                results: outcome
            )
            isRunning = false
        }
    }

    private func color(for status: CapabilityStatus) -> Color {
        switch status {
        case .available: .green
        case .unavailable: .orange
        case .error: .red
        }
    }
}

#Preview {
    NavigationStack {
        DiagnosticsView()
            .environment(AppComposition())
    }
}
