import MMConversation
import MMSecurity
import SwiftUI

struct ProviderProfileEditorSheet: View {
    @Environment(AppComposition.self) private var composition
    @Environment(\.dismiss) private var dismiss

    let role: ProviderRole
    let existing: ProviderProfile?
    let onSaved: () -> Void

    @State private var name: String = ""
    @State private var selectedDriverID: String = ""
    @State private var primarySecretDraft: String = ""
    @State private var secondarySecretDraft: String = ""
    @State private var clearExistingCredentials: Bool = false
    @State private var customEndpoint: String = ""
    @State private var modelName: String = ""
    @State private var voiceID: String = ""
    @State private var existingCredentialStatus: CredentialStatus?
    @State private var errorMessage: String?

    private var availableDrivers: [ProviderDriverDescriptor] {
        composition.providerRegistry.descriptors(for: role)
    }

    private var selectedDriver: ProviderDriverDescriptor? {
        availableDrivers.first(where: { $0.id == selectedDriverID })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(role.purposeDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("基本配置") {
                    TextField("自定义名称（如：主力 / 备用）", text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if availableDrivers.isEmpty {
                        Text("当前没有已注册的协议驱动")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("协议驱动", selection: $selectedDriverID) {
                            if !selectedDriverID.isEmpty, selectedDriver == nil {
                                Text("未注册驱动（\(selectedDriverID)）").tag(selectedDriverID)
                            }
                            ForEach(availableDrivers) { descriptor in
                                Text(descriptor.displayName).tag(descriptor.id)
                            }
                        }
                        if let driver = selectedDriver {
                            Text(driver.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if !selectedDriverID.isEmpty {
                            Text("该配置绑定的协议驱动当前未注册，请重新选择可用驱动。")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                Section {
                    SecureField(primarySecretPlaceholder, text: $primarySecretDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField("附加凭证（可选，如 AppID / Secret）", text: $secondarySecretDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if let status = existingCredentialStatus, status.isConfigured, !clearExistingCredentials {
                        HStack {
                            Text(status.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("清除凭证", role: .destructive) {
                                clearExistingCredentials = true
                                primarySecretDraft = ""
                                secondarySecretDraft = ""
                            }
                            .font(.caption)
                        }
                    } else if clearExistingCredentials {
                        Text("保存时将清除当前已存凭证")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("凭证（仅存 Keychain）")
                } footer: {
                    if selectedDriver?.requiresPrimarySecret == false {
                        Text("当前所选驱动无需凭证即可离线运行；如填写也会安全保存至 Keychain。")
                    } else {
                        Text("凭证加密保存在本机 Keychain，不写入配置文件，且不会明文回显。")
                    }
                }

                Section("高级自定义（可选，留空走驱动默认）") {
                    TextField("自定义 Endpoint（https:// 或 wss://）", text: $customEndpoint)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("模型 / 资源名", text: $modelName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if role == .emotionalTTS || !voiceID.isEmpty {
                        TextField("音色 ID", text: $voiceID)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }
            }
            .navigationTitle(existing == nil ? "添加配置" : "编辑配置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedDriverID.isEmpty)
                }
            }
            .onAppear(perform: populateInitialState)
            .onDisappear {
                // Immediately scrub plaintext secret drafts from view state on dismiss.
                primarySecretDraft = ""
                secondarySecretDraft = ""
            }
            .alert("保存失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var primarySecretPlaceholder: String {
        if let status = existingCredentialStatus, status.isConfigured, !clearExistingCredentials {
            return "主凭证 / API Key（留空保持不变）"
        }
        if selectedDriver?.requiresPrimarySecret == false {
            return "主凭证 / API Key（可选）"
        }
        return "主凭证 / API Key"
    }

    private func populateInitialState() {
        if let existing {
            name = existing.name
            selectedDriverID = existing.driverID
            customEndpoint = existing.customEndpoint ?? ""
            modelName = existing.modelName ?? ""
            voiceID = existing.voiceID ?? ""
            existingCredentialStatus = composition.credentialStore.status(for: existing.id)
        } else {
            selectedDriverID = availableDrivers.first?.id ?? ""
        }
    }

    private func save() {
        let now = composition.clock.now
        let isNew = existing == nil
        let profile = ProviderProfile(
            id: existing?.id ?? UUID(),
            role: role,
            name: name,
            driverID: selectedDriverID,
            customEndpoint: customEndpoint,
            modelName: modelName,
            voiceID: voiceID,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )

        let trimmedPrimary = primarySecretDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSecondary = secondarySecretDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let secretsToRedact = [trimmedPrimary, trimmedSecondary].filter { !$0.isEmpty }

        do {
            try composition.profileStore.save(profile)
            do {
                if clearExistingCredentials && trimmedPrimary.isEmpty && trimmedSecondary.isEmpty {
                    try composition.credentialStore.delete(for: profile.id)
                } else if !trimmedPrimary.isEmpty || !trimmedSecondary.isEmpty {
                    // Merge with existing Keychain credentials when editing without ever echoing secrets in UI.
                    let existingCreds: ProviderCredentials? = (isNew || clearExistingCredentials)
                        ? nil
                        : (try composition.credentialStore.load(for: profile.id))

                    let resolvedPrimary = !trimmedPrimary.isEmpty
                        ? trimmedPrimary
                        : (existingCreds?.primarySecret ?? "")
                    guard !resolvedPrimary.isEmpty else {
                        throw CredentialStoreError.emptyPrimarySecret
                    }

                    let resolvedSecondary: String? = !trimmedSecondary.isEmpty
                        ? trimmedSecondary
                        : existingCreds?.secondarySecret

                    let creds = ProviderCredentials(
                        primarySecret: resolvedPrimary,
                        secondarySecret: resolvedSecondary
                    )
                    try composition.credentialStore.save(creds, for: profile.id)
                }
            } catch {
                // Roll back profile metadata on Keychain failure for both create and edit flows.
                if isNew {
                    try? composition.profileStore.delete(id: profile.id)
                } else if let existing {
                    try? composition.profileStore.save(existing)
                }
                throw error
            }

            primarySecretDraft = ""
            secondarySecretDraft = ""
            onSaved()
            dismiss()
        } catch {
            errorMessage = SecretRedactor.sanitizedErrorMessage(error, secrets: secretsToRedact)
        }
    }
}
