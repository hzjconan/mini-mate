import MMSecurity
import SwiftUI

struct SettingsView: View {
    @Environment(AppComposition.self) private var composition

    @State private var drafts: [VendorID: String] = [:]
    @State private var statuses: [VendorID: CredentialStatus] = [:]
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section("API Key") {
                ForEach(VendorID.allCases, id: \.self) { vendor in
                    VendorCredentialRow(
                        vendor: vendor,
                        status: statuses[vendor],
                        draft: Binding(
                            get: { drafts[vendor] ?? "" },
                            set: { drafts[vendor] = $0 }
                        ),
                        onSave: { save(vendor) },
                        onDelete: { delete(vendor) }
                    )
                }
            }
            Section("诊断") {
                NavigationLink("能力探测") {
                    DiagnosticsView()
                }
            }
        }
        .navigationTitle("设置")
        .onAppear(perform: refresh)
        .alert("操作失败", isPresented: .constant(errorMessage != nil)) {
            Button("好") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func save(_ vendor: VendorID) {
        do {
            try composition.credentialStore.save(key: drafts[vendor] ?? "", for: vendor)
            drafts[vendor] = ""
            refresh()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func delete(_ vendor: VendorID) {
        do {
            try composition.credentialStore.delete(for: vendor)
            refresh()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func refresh() {
        statuses = Dictionary(
            uniqueKeysWithValues: VendorID.allCases.map {
                ($0, composition.credentialStore.status(for: $0))
            }
        )
    }
}

private struct VendorCredentialRow: View {
    let vendor: VendorID
    let status: CredentialStatus?
    @Binding var draft: String
    let onSave: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(vendor.title)
                Spacer()
                Text(status?.description ?? "未配置")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                SecureField("API Key", text: $draft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("保存", action: onSave)
                    .disabled(draft.isEmpty)
                if status?.isConfigured == true {
                    Button("删除", role: .destructive, action: onDelete)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environment(AppComposition(credentialStore: InMemoryCredentialStore()))
    }
}
