import SwiftUI

struct CloudSyncSettingsView: View {
    @EnvironmentObject private var cloudSyncManager: CloudSyncManager

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                settingsSection("Status") {
                    settingsInlineRow("iCloud Sync") {
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

                    settingsInlineRow("Last synced") {
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

                settingsSection("Sync") {
                    Toggle("iCloud Sync", isOn: $cloudSyncManager.isSyncEnabled)
                        .tint(AppTheme.accent)

                    Text("Sync reading progress, library metadata, settings, and stats across your Apple devices.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        cloudSyncManager.syncNow()
                    } label: {
                        Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                    .disabled(!cloudSyncManager.isSyncEnabled || cloudSyncManager.status.kind == .syncing)
                }

                settingsSection("Document Files") {
                    settingsInlineRow("File sync") {
                        Text("Metadata only")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                    }

                    Text("Large document files are not uploaded automatically. FocusRead syncs metadata first so future file syncing can be added safely.")
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
        .navigationTitle("iCloud Sync")
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
            return "iCloud Sync is not configured for this build."
        case .error:
            return "Sync failed. Try again later."
        default:
            return ""
        }
    }

    private var syncStatusText: String {
        switch cloudSyncManager.status.kind {
        case .off:
            return "Off"
        case .unavailable:
            return "Unavailable"
        case .syncing:
            return "Syncing"
        case .synced:
            return "On"
        case .error:
            return "Error"
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
            return "Never"
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
