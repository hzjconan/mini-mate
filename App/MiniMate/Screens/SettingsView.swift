import MMConversation
import MMSecurity
import SwiftUI

struct SettingsView: View {
    @Environment(AppComposition.self) private var composition

    @State private var profilesByRole: [ProviderRole: [ProviderProfile]] = [:]
    @State private var activeIDByRole: [ProviderRole: UUID] = [:]
    @State private var statusesByID: [UUID: CredentialStatus] = [:]
    @State private var editorContext: EditorContext?
    @State private var errorMessage: String?

    private struct EditorContext: Identifiable {
        let id = UUID()
        let role: ProviderRole
        let existing: ProviderProfile?
    }

    var body: some View {
        List {
            if let loadError = composition.profileStoreLoadError {
                Section {
                    Label("配置读取异常，已暂用临时内存模式：\(loadError)", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }

            ForEach(ProviderRole.allCases) { role in
                roleSection(for: role)
            }

            Section("诊断") {
                NavigationLink("能力探测") {
                    DiagnosticsView()
                }
            }
        }
        .navigationTitle("设置")
        .onAppear(perform: refresh)
        .sheet(item: $editorContext) { context in
            ProviderProfileEditorSheet(
                role: context.role,
                existing: context.existing,
                onSaved: refresh
            )
            .environment(composition)
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func roleSection(for role: ProviderRole) -> some View {
        let profiles = profilesByRole[role] ?? []
        let activeID = activeIDByRole[role]

        Section {
            if profiles.isEmpty {
                Text("尚未添加配置")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(profiles) { profile in
                    ProfileRow(
                        profile: profile,
                        driverName: driverDisplayName(for: profile.driverID),
                        credentialStatus: statusesByID[profile.id],
                        isActive: activeID == profile.id,
                        onSelect: { setActive(profile) },
                        onEdit: { editorContext = EditorContext(role: role, existing: profile) }
                    )
                }
                .onDelete { offsets in
                    deleteProfiles(at: offsets, in: profiles)
                }
            }

            Button {
                editorContext = EditorContext(role: role, existing: nil)
            } label: {
                Label(addButtonTitle(for: role), systemImage: "plus.circle")
            }
        } header: {
            Text(role.displayTitle)
        } footer: {
            Text(role.purposeDescription)
        }
    }

    private func addButtonTitle(for role: ProviderRole) -> String {
        switch role {
        case .realtimeBrain:
            "添加对话大脑配置"
        case .emotionalTTS:
            "添加声音合成配置"
        }
    }

    private func driverDisplayName(for driverID: String) -> String {
        composition.providerRegistry.descriptor(id: driverID)?.displayName ?? driverID
    }

    private func setActive(_ profile: ProviderProfile) {
        do {
            try composition.profileStore.setActive(id: profile.id, for: profile.role)
            refresh()
        } catch {
            errorMessage = SecretRedactor.sanitizedErrorMessage(error)
        }
    }

    private func deleteProfiles(at offsets: IndexSet, in profiles: [ProviderProfile]) {
        defer { refresh() }
        do {
            for index in offsets {
                let profile = profiles[index]
                // Delete Keychain credentials first so no orphaned secrets remain.
                try composition.credentialStore.delete(for: profile.id)
                try composition.profileStore.delete(id: profile.id)
            }
        } catch {
            errorMessage = SecretRedactor.sanitizedErrorMessage(error)
        }
    }

    private func refresh() {
        var nextProfiles: [ProviderRole: [ProviderProfile]] = [:]
        var nextActive: [ProviderRole: UUID] = [:]
        var nextStatuses: [UUID: CredentialStatus] = [:]

        for role in ProviderRole.allCases {
            let list = composition.profileStore.profiles(for: role)
            nextProfiles[role] = list
            if let active = composition.profileStore.activeProfileID(for: role) {
                nextActive[role] = active
            }
            for profile in list {
                nextStatuses[profile.id] = composition.credentialStore.status(for: profile.id)
            }
        }

        profilesByRole = nextProfiles
        activeIDByRole = nextActive
        statusesByID = nextStatuses
    }
}

private struct ProfileRow: View {
    let profile: ProviderProfile
    let driverName: String
    let credentialStatus: CredentialStatus?
    let isActive: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onSelect) {
                HStack(spacing: 10) {
                    Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(profile.name)
                                .font(.body)
                                .foregroundStyle(.primary)
                            if isActive {
                                Text("当前启用")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.15))
                                    .foregroundStyle(Color.accentColor)
                                    .clipShape(Capsule())
                            }
                        }
                        Text("\(driverName) · \(credentialStatus?.description ?? "未配置")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button("编辑", action: onEdit)
                .font(.subheadline)
                .buttonStyle(.borderless)
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environment(AppComposition(
                credentialStore: InMemoryCredentialStore(),
                profileStore: InMemoryProviderProfileStore(),
                providerRegistry: .makeDefault()
            ))
    }
}
