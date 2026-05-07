import SwiftUI

struct AppLanguageSettingsView: View {
    @Binding var selectedLanguageRawValue: String
    @Environment(\.focusReadTheme) private var theme
    @State private var searchText = ""

    private var selectedLanguage: AppLanguage {
        AppLanguage(rawValue: selectedLanguageRawValue) ?? .systemDefault
    }

    private var visibleLanguages: [AppLanguage] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return AppLanguage.selectableLanguages
        }

        return AppLanguage.selectableLanguages.filter { language in
            let searchableParts = [
                language.displayName,
                language.nativeName,
                language.shortCode
            ]
                .compactMap { $0 }
                .joined(separator: " ")

            return searchableParts.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TextField(L10n.string(.languageSearchPlaceholder), text: $searchText)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .textFieldStyle(.roundedBorder)
                    .padding(.bottom, 2)

                VStack(spacing: 0) {
                    ForEach(Array(visibleLanguages.enumerated()), id: \.element.id) { index, language in
                        languageRow(language)

                        if index < visibleLanguages.count - 1 {
                            Divider()
                                .padding(.leading, 62)
                                .opacity(0.45)
                        }
                    }
                }
                .padding(.vertical, 6)
                .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(theme.border, lineWidth: 1)
                }

                Text(.languageNote)
                    .font(.footnote)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)
            }
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .background(FocusReadBackground())
        .navigationTitle(L10n.key(.languageTitle))
        .navigationBarTitleDisplayMode(.inline)
        .tint(theme.accent)
        .focusReadThemeRefresh()
    }

    private func languageRow(_ language: AppLanguage) -> some View {
        Button {
            withAnimation(.smooth(duration: 0.18)) {
                selectedLanguageRawValue = language.rawValue
            }
        } label: {
            HStack(spacing: 12) {
                languageIcon(language)

                VStack(alignment: .leading, spacing: 3) {
                    Text(language.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.primaryText)

                    if let subtitle = subtitle(for: language) {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(theme.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                }

                Spacer(minLength: 12)

                if selectedLanguage == language {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(theme.accent)
                        .accessibilityLabel(L10n.string(.commonSelected))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(selectedLanguage == language ? L10n.string(.commonSelected) : L10n.string(.commonNotSelected))
    }

    @ViewBuilder
    private func languageIcon(_ language: AppLanguage) -> some View {
        if language == .systemDefault {
            Image(systemName: language.symbolName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 38, height: 38)
                .background(theme.controlBackground, in: Circle())
        } else {
            Text(language.shortCode)
                .font(.caption2.weight(.bold))
                .foregroundStyle(theme.accent)
                .frame(width: 38, height: 38)
                .background(theme.controlBackground, in: Circle())
        }
    }

    private func subtitle(for language: AppLanguage) -> String? {
        if language == .systemDefault {
            return L10n.format(.languageSystemSubtitle, AppLanguage.preferredSystemLanguage().displayName)
        }

        guard let nativeName = language.nativeName,
              nativeName != language.displayName else {
            return nil
        }

        return nativeName
    }
}
