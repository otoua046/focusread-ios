import SwiftUI

struct CloudSyncSettingsView: View {
    @EnvironmentObject private var cloudSyncManager: CloudSyncManager

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                settingsSection(L10n.string(.cloudSyncStatus)) {
                    settingsInlineRow(L10n.string(.cloudSyncTitle)) {
                        HStack(spacing: 8) {
                            if cloudSyncManager.status.kind == .syncing {
                                ProgressView()
                                    .controlSize(.small)
                            }

                            Text(syncStatusText)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(syncStatusColor)
                        }
                    }

                    Divider().foregroundStyle(AppTheme.border)

                    settingsInlineRow(L10n.string(.cloudSyncLastSynced)) {
                        Text(lastSyncedText)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                    }

                    if shouldShowStatusMessage {
                        Divider().foregroundStyle(AppTheme.border)

                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(cloudSyncManager.status.kind == .error ? AppTheme.destructive : AppTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                settingsSection(L10n.string(.settingsSectionSync)) {
                    Toggle(L10n.string(.cloudSyncTitle), isOn: $cloudSyncManager.isSyncEnabled)
                        .tint(AppTheme.accent)

                    Text(.cloudSyncDescription)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        cloudSyncManager.syncNow()
                    } label: {
                        Label(.cloudSyncNow, systemImage: "arrow.triangle.2.circlepath")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.focusReadProminentAction(font: .subheadline.weight(.semibold)))
                    .disabled(!cloudSyncManager.isSyncEnabled || cloudSyncManager.status.kind == .syncing)
                }

                settingsSection(L10n.string(.cloudSyncDocumentFiles)) {
                    settingsInlineRow(L10n.string(.cloudSyncFileSync)) {
                        Text(.cloudSyncMetadataOnly)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                    }

                    Text(.cloudSyncDocumentFilesDescription)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .focusReadSettingsPageChrome()
        .navigationTitle(L10n.key(.cloudSyncTitle))
        .navigationBarTitleDisplayMode(.inline)
        .tint(AppTheme.accent)
        .focusReadThemeRefresh()
    }

    private var shouldShowStatusMessage: Bool {
        cloudSyncManager.status.kind == .unavailable || cloudSyncManager.status.kind == .error
    }

    private var statusMessage: String {
        cloudSyncManager.status.message ?? fallbackStatusMessage
    }

    private var fallbackStatusMessage: String {
        switch cloudSyncManager.status.kind {
        case .unavailable:
            return L10n.string(.cloudSyncUnavailableMessage)
        case .error:
            return L10n.string(.cloudSyncFailedMessage)
        default:
            return ""
        }
    }

    private var syncStatusText: String {
        switch cloudSyncManager.status.kind {
        case .off:
            return L10n.string(.settingsStatusOff)
        case .unavailable:
            return L10n.string(.settingsStatusUnavailable)
        case .syncing:
            return L10n.string(.settingsStatusSyncing)
        case .synced:
            return L10n.string(.settingsStatusOn)
        case .error:
            return L10n.string(.settingsStatusError)
        }
    }

    private var syncStatusColor: Color {
        switch cloudSyncManager.status.kind {
        case .synced:
            return AppTheme.accent
        case .error:
            return AppTheme.destructive
        default:
            return AppTheme.secondaryText
        }
    }

    private var lastSyncedText: String {
        guard let lastSyncedAt = cloudSyncManager.status.lastSyncedAt else {
            return L10n.string(.settingsStatusNever)
        }
        return lastSyncedAt.formatted(date: .abbreviated, time: .shortened)
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
                .textCase(.uppercase)
                .tracking(0.08)
                .padding(.horizontal, 6)

            VStack(alignment: .leading, spacing: 14) {
                content()
            }
            .padding(18)
            .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(AppTheme.border, lineWidth: 1)
            }
        }
    }

    private func settingsInlineRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)

            Spacer(minLength: 12)

            content()
        }
    }
}
