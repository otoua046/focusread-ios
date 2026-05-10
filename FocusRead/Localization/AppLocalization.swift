import Foundation
import SwiftUI

enum AppLanguageStorageKey {
    static let selectedLanguage = "appLanguage.selected"
}

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case systemDefault = "system"
    case english = "en"
    case french = "fr"
    case spanish = "es"
    case arabic = "ar"
    case german = "de"
    case italian = "it"
    case portuguese = "pt"
    case chineseSimplified = "zh-Hans"
    case japanese = "ja"
    case korean = "ko"

    var id: String { rawValue }

    static var selectableLanguages: [AppLanguage] {
        allCases
    }

    static var supportedLanguages: [AppLanguage] {
        allCases.filter { $0 != .systemDefault }
    }

    var localeIdentifier: String? {
        switch self {
        case .systemDefault:
            return nil
        default:
            return rawValue
        }
    }

    var resolvedLanguage: AppLanguage {
        self == .systemDefault ? Self.preferredSystemLanguage() : self
    }

    var resolvedLocaleIdentifier: String {
        resolvedLanguage.rawValue
    }

    var layoutDirection: LayoutDirection {
        resolvedLanguage == .arabic ? .rightToLeft : .leftToRight
    }

    var locale: Locale {
        guard self != .systemDefault else {
            return .autoupdatingCurrent
        }
        return Locale(identifier: resolvedLocaleIdentifier)
    }

    var displayName: String {
        switch self {
        case .systemDefault:
            return L10n.string(.languageSystemDefault)
        case .english:
            return L10n.string(.languageEnglish)
        case .french:
            return L10n.string(.languageFrench)
        case .spanish:
            return L10n.string(.languageSpanish)
        case .arabic:
            return L10n.string(.languageArabic)
        case .german:
            return L10n.string(.languageGerman)
        case .italian:
            return L10n.string(.languageItalian)
        case .portuguese:
            return L10n.string(.languagePortuguese)
        case .chineseSimplified:
            return L10n.string(.languageChineseSimplified)
        case .japanese:
            return L10n.string(.languageJapanese)
        case .korean:
            return L10n.string(.languageKorean)
        }
    }

    var nativeName: String? {
        switch self {
        case .systemDefault:
            return nil
        case .english:
            return "English"
        case .french:
            return "Français"
        case .spanish:
            return "Español"
        case .arabic:
            return "العربية"
        case .german:
            return "Deutsch"
        case .italian:
            return "Italiano"
        case .portuguese:
            return "Português"
        case .chineseSimplified:
            return "简体中文"
        case .japanese:
            return "日本語"
        case .korean:
            return "한국어"
        }
    }

    var shortCode: String {
        switch self {
        case .systemDefault:
            return "SYS"
        case .english:
            return "EN"
        case .french:
            return "FR"
        case .spanish:
            return "ES"
        case .arabic:
            return "AR"
        case .german:
            return "DE"
        case .italian:
            return "IT"
        case .portuguese:
            return "PT"
        case .chineseSimplified:
            return "ZH"
        case .japanese:
            return "JA"
        case .korean:
            return "KO"
        }
    }

    var symbolName: String {
        switch self {
        case .systemDefault:
            return "globe"
        default:
            return "character.bubble"
        }
    }

    static var selected: AppLanguage {
        let rawValue = UserDefaults.standard.string(forKey: AppLanguageStorageKey.selectedLanguage)
        return AppLanguage(rawValue: rawValue ?? "") ?? .systemDefault
    }

    static func preferredSystemLanguage(
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> AppLanguage {
        for identifier in preferredLanguages {
            if let language = supportedLanguage(for: identifier) {
                return language
            }
        }

        return .english
    }

    private static func supportedLanguage(for identifier: String) -> AppLanguage? {
        let normalized = identifier
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()

        if normalized.hasPrefix("zh-hans")
            || normalized.hasPrefix("zh-cn")
            || normalized.hasPrefix("zh-sg") {
            return .chineseSimplified
        }

        if normalized.hasPrefix("en") { return .english }
        if normalized.hasPrefix("fr") { return .french }
        if normalized.hasPrefix("es") { return .spanish }
        if normalized.hasPrefix("ar") { return .arabic }
        if normalized.hasPrefix("de") { return .german }
        if normalized.hasPrefix("it") { return .italian }
        if normalized.hasPrefix("pt") { return .portuguese }
        if normalized.hasPrefix("ja") { return .japanese }
        if normalized.hasPrefix("ko") { return .korean }

        return nil
    }
}

enum L10n {
    enum Key: String {
        case commonDone = "common.done"
        case commonCancel = "common.cancel"
        case commonSave = "common.save"
        case commonDelete = "common.delete"
        case commonOK = "common.ok"
        case commonRetry = "common.retry"
        case commonSelected = "common.selected"
        case commonNotSelected = "common.notSelected"
        case commonWords = "common.words"

        case tabHome = "tab.home"
        case tabLibrary = "tab.library"
        case tabStats = "tab.stats"
        case tabSettings = "tab.settings"

        case languageTitle = "language.title"
        case languageSystemDefault = "language.systemDefault"
        case languageSystemSubtitle = "language.systemSubtitle"
        case languageNote = "language.note"
        case languageSearchPlaceholder = "language.search.placeholder"
        case languageEnglish = "language.english"
        case languageFrench = "language.french"
        case languageSpanish = "language.spanish"
        case languageArabic = "language.arabic"
        case languageGerman = "language.german"
        case languageItalian = "language.italian"
        case languagePortuguese = "language.portuguese"
        case languageChineseSimplified = "language.chineseSimplified"
        case languageJapanese = "language.japanese"
        case languageKorean = "language.korean"

        case settingsTitle = "settings.title"
        case settingsAppAppearance = "settings.section.appAppearance"
        case settingsAppearance = "settings.appearance"
        case settingsAppLanguage = "settings.appLanguage"
        case settingsTheme = "settings.theme"
        case settingsTypography = "settings.typography"
        case settingsReaderBehavior = "settings.section.readerBehavior"
        case settingsDefaultWPM = "settings.defaultWPM"
        case settingsDisplayMode = "settings.displayMode"
        case settingsAnchorLetter = "settings.anchorLetter"
        case settingsHaptics = "settings.haptics"
        case settingsReverseWPMDrag = "settings.reverseWPMDrag"
        case settingsPunctuationPauses = "settings.punctuationPauses"
        case settingsLongWordDelay = "settings.longWordDelay"
        case settingsDisplayModeHelp = "settings.displayMode.help"
        case settingsAnchorLetterHelp = "settings.anchorLetter.help"
        case settingsPunctuationPausesHelp = "settings.punctuationPauses.help"
        case settingsLongWordDelayHelp = "settings.longWordDelay.help"
        case settingsProgress = "settings.section.progress"
        case settingsDailyGoal = "settings.dailyGoal"
        case settingsTextCleanup = "settings.section.textCleanup"
        case settingsImportedText = "settings.importedText"
        case settingsCleanupDescriptionFormat = "settings.cleanupDescription.format"
        case settingsAIFeatures = "settings.section.aiFeatures"
        case settingsAIRecaps = "settings.aiRecaps"
        case settingsEnableAIRecaps = "settings.enableAIRecaps"
        case settingsAIRecapsDescription = "settings.aiRecaps.description"
        case settingsAIRecapsUnavailable = "settings.aiRecaps.unavailable"
        case settingsAboutReset = "settings.section.aboutReset"
        case settingsResetTypography = "settings.resetTypography"
        case settingsResetAll = "settings.resetAll"

        case appearanceSystem = "appearance.system"
        case appearanceLight = "appearance.light"
        case appearanceDark = "appearance.dark"
        case displayModeOneWord = "displayMode.oneWord"
        case displayModeTwoWords = "displayMode.twoWords"
        case longWordDelayOff = "longWordDelay.off"
        case longWordDelayModerate = "longWordDelay.moderate"
        case longWordDelayStrong = "longWordDelay.strong"
        case cleanupOff = "cleanup.off"
        case cleanupSmart = "cleanup.smart"
        case cleanupAI = "cleanup.ai"
        case cleanupOffDescription = "cleanup.off.description"
        case cleanupSmartDescription = "cleanup.smart.description"
        case cleanupAIDescription = "cleanup.ai.description"
        case fontFamilySerif = "fontFamily.serif"
        case fontFamilySystem = "fontFamily.system"
        case fontFamilyRounded = "fontFamily.rounded"
        case fontFamilyMonospaced = "fontFamily.monospaced"
        case fontWeightRegular = "fontWeight.regular"
        case fontWeightMedium = "fontWeight.medium"
        case fontWeightBold = "fontWeight.bold"
        case textColorPrimary = "textColor.primary"
        case textColorBlack = "textColor.black"
        case textColorGray = "textColor.gray"
        case textColorBlue = "textColor.blue"
        case textColorSepia = "textColor.sepia"
        case typographyFont = "typography.section.font"
        case typographyFontFamily = "typography.fontFamily"
        case typographyFontSize = "typography.fontSize"
        case typographyFontWeight = "typography.fontWeight"
        case typographyItalic = "typography.italic"
        case typographyTextColor = "typography.textColor"
        case typographyPreview = "typography.preview"
        case typographyPreviewWord = "typography.preview.word"
        case typographySummaryItalic = "typography.summary.italic"
        case themeCategoryAccent = "theme.category.accent"
        case themeCategoryFull = "theme.category.full"

        case homeHeroSubtitle = "home.hero.subtitle"
        case homeDemoSample = "home.demo.sample"
        case homeHeroWords = "home.hero.words"
        case homeComparisonWords = "home.comparison.words"
        case homeAnimatedDemoAccessibility = "home.animatedDemo.accessibility"
        case homeSeeShift = "home.seeShift"
        case homeModeNormal = "home.mode.normal"
        case homeModeFocusRead = "home.mode.focusRead"
        case homeNormalReadingDescription = "home.normalReading.description"
        case homeReadingGoalPrompt = "home.readingGoal.prompt"
        case homeGoalStudy = "home.goal.study"
        case homeGoalBooks = "home.goal.books"
        case homeGoalFocus = "home.goal.focus"
        case homeGoalWork = "home.goal.work"
        case homeGoalLanguages = "home.goal.languages"
        case homeAIRecapEnabledTitle = "home.aiRecap.enabled.title"
        case homeAIRecapUnavailableTitle = "home.aiRecap.unavailable.title"
        case homeAIRecapEnabledStatus = "home.aiRecap.enabled.status"
        case homeAIRecapAvailableStatus = "home.aiRecap.available.status"
        case homeAIRecapRequiresStatus = "home.aiRecap.requires.status"
        case homeRecapFlowRead = "home.recapFlow.read"
        case homeRecapFlowRecap = "home.recapFlow.recap"
        case homeRecapFlowKeyIdeas = "home.recapFlow.keyIdeas"
        case homeReadingSpace = "home.readingSpace"
        case homeThemes = "home.themes"
        case homeTryFocusRead = "home.tryFocusRead"
        case homeImportBook = "home.importBook"
        case homePremiumPreviewTitle = "home.premiumPreview.title"
        case homePremiumMessage = "home.premiumPreview.message"
        case homePremiumTeaser = "home.premium.teaser"
        case homeViewPremium = "home.viewPremium"

        case importTitle = "import.title"
        case importCloseAccessibility = "import.close.accessibility"
        case importDocumentDetailFormat = "import.document.detail.format"
        case importStartReading = "import.startReading"
        case importChooseAnotherFile = "import.chooseAnotherFile"
        case importSourceFiles = "import.source.files"
        case importSourceCamera = "import.source.camera"
        case importSourcePhotoLibrary = "import.source.photoLibrary"
        case importSourceImageOCR = "import.source.imageOCR"
        case importProgressExtractingText = "import.progress.extractingText"
        case importProgressRecognizingText = "import.progress.recognizingText"
        case importUnitPages = "import.unit.pages"
        case importUnitImages = "import.unit.images"
        case importProgressDetailFormat = "import.progress.detail.format"
        case importCameraScan = "import.cameraScan"
        case importPhotoImport = "import.photoImport"
        case importErrorCancelledTitle = "import.error.cancelled.title"
        case importErrorFileCopyTitle = "import.error.fileCopy.title"
        case importErrorInvalidTextEncodingTitle = "import.error.invalidTextEncoding.title"
        case importErrorUnreadablePDFTitle = "import.error.unreadablePDF.title"
        case importErrorNoReadableTextTitle = "import.error.noReadableText.title"
        case importErrorOCRFailedTitle = "import.error.ocrFailed.title"
        case importErrorInvalidEPUBTitle = "import.error.invalidEPUB.title"
        case importErrorEPUBContentsNotFoundTitle = "import.error.epubContentsNotFound.title"
        case importErrorEPUBNoReadableTextTitle = "import.error.epubNoReadableText.title"
        case importErrorEPUBExtractionFailedTitle = "import.error.epubExtractionFailed.title"
        case importErrorCameraUnavailableTitle = "import.error.cameraUnavailable.title"
        case importErrorCameraAccessDeniedTitle = "import.error.cameraAccessDenied.title"
        case importErrorImageImportFailedTitle = "import.error.imageImportFailed.title"
        case importErrorUnsupportedFileTitle = "import.error.unsupportedFile.title"
        case importErrorCancelledMessage = "import.error.cancelled.message"
        case importErrorFileCopyMessage = "import.error.fileCopy.message"
        case importErrorInvalidTextEncodingMessage = "import.error.invalidTextEncoding.message"
        case importErrorUnreadablePDFMessage = "import.error.unreadablePDF.message"
        case importErrorNoReadableTextMessage = "import.error.noReadableText.message"
        case importErrorOCRFailedMessage = "import.error.ocrFailed.message"
        case importErrorInvalidEPUBMessage = "import.error.invalidEPUB.message"
        case importErrorEPUBContentsNotFoundMessage = "import.error.epubContentsNotFound.message"
        case importErrorEPUBNoReadableTextMessage = "import.error.epubNoReadableText.message"
        case importErrorEPUBExtractionFailedMessage = "import.error.epubExtractionFailed.message"
        case importErrorCameraUnavailableMessage = "import.error.cameraUnavailable.message"
        case importErrorCameraAccessDeniedMessage = "import.error.cameraAccessDenied.message"
        case importErrorImageImportFailedMessage = "import.error.imageImportFailed.message"
        case importErrorUnsupportedFileMessage = "import.error.unsupportedFile.message"

        case libraryTitle = "library.title"
        case libraryImportAccessibility = "library.import.accessibility"
        case librarySearchPlaceholder = "library.search.placeholder"
        case libraryDeleteReadTitle = "library.deleteRead.title"
        case libraryDeleteReadMessage = "library.deleteRead.message"
        case libraryDeleteAllTitle = "library.deleteAll.title"
        case libraryDeleteSelectedTitle = "library.deleteSelected.title"
        case libraryDeleteSelectedMessage = "library.deleteSelected.message"
        case librarySelectAll = "library.selectAll"
        case libraryDeselectAll = "library.deselectAll"
        case librarySelectedCountFormat = "library.selectedCount.format"
        case libraryEmpty = "library.empty"
        case libraryNoResults = "library.noResults"
        case libraryNoResultsSuggestion = "library.noResults.suggestion"
        case libraryAIRecap = "library.aiRecap"
        case libraryMarkFinished = "library.markFinished"
        case libraryRename = "library.rename"
        case libraryRenameTitleSection = "library.rename.titleSection"
        case libraryReadTitlePlaceholder = "library.rename.placeholder"
        case librarySelect = "library.select"
        case libraryViewAs = "library.viewAs"
        case libraryGrid = "library.grid"
        case libraryList = "library.list"
        case librarySortBy = "library.sortBy"
        case librarySortRecent = "library.sort.recent"
        case librarySortTitle = "library.sort.title"
        case librarySortAuthor = "library.sort.author"
        case librarySortManual = "library.sort.manual"
        case librarySourcePasted = "library.source.pasted"
        case librarySourceText = "library.source.text"
        case librarySourceImage = "library.source.image"

        case readerPreviousSection = "reader.previousSection"
        case readerRewindWord = "reader.rewindWord"
        case readerPause = "reader.pause"
        case readerPlay = "reader.play"
        case readerSkipWord = "reader.skipWord"
        case readerNextSection = "reader.nextSection"
        case readerDecreaseSpeed = "reader.decreaseSpeed"
        case readerIncreaseSpeed = "reader.increaseSpeed"
        case readerSpeed = "reader.speed"
        case readerSpeedValueFormat = "reader.speedValue.format"
        case readerWPMBadgeFormat = "reader.wpmBadge.format"
        case readerSpeedHint = "reader.speed.hint"
        case readerNoDefinitionFound = "reader.noDefinitionFound"
        case readerClose = "reader.close"
        case readerCurrentLocation = "reader.currentLocation"
        case readerCurrentLocationHint = "reader.currentLocation.hint"
        case readerProgress = "reader.progress"
        case readerProgressHint = "reader.progress.hint"
        case readerSearchWordAction = "reader.searchWord.action"
        case readerCurrentLocationTitle = "reader.currentLocation.title"
        case readerWordLocationFormat = "reader.wordLocation.format"
        case readerPageLocationFormat = "reader.pageLocation.format"
        case readerChapterWithTitleFormat = "reader.chapterWithTitle.format"
        case readerChapterFormat = "reader.chapter.format"
        case readerRecapWordProgressFormat = "reader.recapWordProgress.format"
        case readerWordProgressFormat = "reader.wordProgress.format"
        case readerRecapMode = "reader.recapMode"
        case readerAIRecap = "reader.aiRecap"
        case readerPastedText = "reader.pastedText"
        case readerPageFormat = "reader.page.format"
        case readerSectionFormat = "reader.section.format"
        case readerPartFormat = "reader.part.format"
        case readerDocumentLocationFormat = "reader.documentLocation.format"
        case readerPagesRangeLocationFormat = "reader.pagesRangeLocation.format"
        case readerQuickActions = "reader.quickActions"
        case readerCloseQuickActions = "reader.closeQuickActions"
        case readerQuickActionsHint = "reader.quickActions.hint"
        case readerTranslate = "reader.translate"
        case readerSettings = "reader.settings"
        case readerDictionary = "reader.dictionary"
        case readerLookup = "reader.lookup"
        case readerDictionaryHint = "reader.dictionary.hint"
        case readerDictionaryCurrentWordHintFormat = "reader.dictionaryCurrentWord.hint.format"
        case readerActionOpenHint = "reader.actionOpen.hint"
        case readerDemoTitle = "reader.demoTitle"

        case searchTitle = "search.title"
        case searchFindWords = "search.findWords"
        case searchSearching = "search.searching"
        case searchNoMatches = "search.noMatches"
        case searchWordResultFormat = "search.wordResult.format"

        case statsTitle = "stats.title"
        case statsRecentDays = "stats.recentDays"
        case statsEmptyRecentDays = "stats.emptyRecentDays"
        case statsReadingActivity = "stats.readingActivity"
        case statsReadingActivityAccessibility = "stats.readingActivity.accessibility"
        case statsLess = "stats.less"
        case statsMore = "stats.more"
        case statsDailyProgress = "stats.dailyProgress"
        case statsDailyProgressAccessibilityFormat = "stats.dailyProgress.accessibility.format"
        case statsDailyStreak = "stats.dailyStreak"
        case statsBestStreakFormat = "stats.bestStreak.format"
        case statsAverageWPM = "stats.averageWPM"
        case statsReadingTime = "stats.readingTime"
        case statsBooksCompleted = "stats.booksCompleted"
        case statsTimeSaved = "stats.timeSaved"
        case statsTimeSavedDetail = "stats.timeSaved.detail"
        case statsWordsReadFormat = "stats.wordsRead.format"
        case statsDurationZero = "stats.duration.zero"
        case statsDurationHoursMinutesFormat = "stats.duration.hoursMinutes.format"
        case statsDurationHoursFormat = "stats.duration.hours.format"
        case statsDurationMinutesFormat = "stats.duration.minutes.format"
        case statsContributionDayAccessibilityFormat = "stats.contributionDay.accessibility.format"
        case statsWeekdayMonday = "stats.weekday.monday"
        case statsWeekdayWednesday = "stats.weekday.wednesday"
        case statsWeekdayFriday = "stats.weekday.friday"

        case aiRecapTitle = "aiRecap.title"
        case aiRecapGeneratedFromLastSession = "aiRecap.generatedFromLastSession"
        case aiRecapNoReadySessions = "aiRecap.noReadySessions"
        case aiRecapTooShort = "aiRecap.tooShort"
        case aiRecapEmptyHint = "aiRecap.emptyHint"
        case aiRecapDisabled = "aiRecap.disabled"
        case aiRecapUnavailable = "aiRecap.unavailable"
        case aiRecapLastSession = "aiRecap.lastSession"
        case aiRecapRecentSession = "aiRecap.recentSession"
        case aiRecapReady = "aiRecap.ready"
        case aiRecapGenerating = "aiRecap.generating"
        case aiRecapGenerate = "aiRecap.generate"
        case aiRecapNoGenerated = "aiRecap.noGenerated"
        case aiRecapRead = "aiRecap.read"
        case aiRecapRSVP = "aiRecap.rsvp"
        case aiRecapRegenerate = "aiRecap.regenerate"
        case aiRecapGeneratedLabel = "aiRecap.generatedLabel"
        case aiRecapNoEligibleSession = "aiRecap.error.noEligibleSession"
        case aiRecapSourceUnavailable = "aiRecap.error.sourceUnavailable"
        case aiRecapUnsupportedLanguage = "aiRecap.error.unsupportedLanguage"
        case aiRecapGenerationFailed = "aiRecap.error.generationFailed"
    }

    static func key(_ key: Key) -> LocalizedStringKey {
        LocalizedStringKey(string(key))
    }

    static func string(_ key: Key, localeIdentifier: String? = nil) -> String {
        let identifier = localeIdentifier ?? AppLanguage.selected.resolvedLocaleIdentifier
        let bundle = localizedBundle(for: identifier)
        let value = bundle.localizedString(forKey: key.rawValue, value: nil, table: nil)
        guard value != key.rawValue else {
            return englishBundle.localizedString(forKey: key.rawValue, value: key.rawValue, table: nil)
        }
        return value
    }

    static func format(_ key: Key, _ arguments: CVarArg..., localeIdentifier: String? = nil) -> String {
        let identifier = localeIdentifier ?? AppLanguage.selected.resolvedLocaleIdentifier
        return String(
            format: string(key, localeIdentifier: identifier),
            locale: Locale(identifier: identifier),
            arguments: arguments
        )
    }

    private static func localizedBundle(for identifier: String) -> Bundle {
        if let path = Bundle.main.path(forResource: identifier, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }

        return englishBundle
    }

    private static var englishBundle: Bundle {
        guard let path = Bundle.main.path(forResource: AppLanguage.english.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }
}

extension LocalizedStringKey {
    init(_ key: L10n.Key) {
        self.init(L10n.string(key))
    }
}

extension Text {
    init(_ key: L10n.Key) {
        self.init(verbatim: L10n.string(key))
    }
}

extension Button where Label == Text {
    init(
        _ key: L10n.Key,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) {
        self.init(role: role, action: action) {
            Text(key)
        }
    }
}

extension Label where Title == Text, Icon == Image {
    init(_ key: L10n.Key, systemImage: String) {
        self.init {
            Text(key)
        } icon: {
            Image(systemName: systemImage)
        }
    }
}

struct FocusReadLocalizationRefreshModifier: ViewModifier {
    @AppStorage(AppLanguageStorageKey.selectedLanguage) private var selectedLanguageRawValue: String = AppLanguage.systemDefault.rawValue

    private var selectedLanguage: AppLanguage {
        AppLanguage(rawValue: selectedLanguageRawValue) ?? .systemDefault
    }

    func body(content: Content) -> some View {
        content
            .environment(\.locale, selectedLanguage.locale)
            .environment(\.layoutDirection, selectedLanguage.layoutDirection)
    }
}

extension View {
    func focusReadLocalizationRefresh() -> some View {
        modifier(FocusReadLocalizationRefreshModifier())
    }
}
