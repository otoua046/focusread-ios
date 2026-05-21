# FocusRead Benchmark Report

Branch: `perf/benchmark-suite`
Base: `codex/liquid-glass-controls` at `782969b`
Date: 2026-05-20

## Environment

| Field | Value |
| --- | --- |
| Device | iPhone 17 Pro Max Simulator |
| Simulator ID | `9EF26532-319C-4E6B-BE6B-01FFB7A2BB16` |
| iOS | 26.2 (`23C54`) |
| Build | Debug, iOS Simulator, `CODE_SIGNING_ALLOWED=NO` |
| Xcode result bundles | Stored outside repo under `~/Library/Developer/XcodeBuildMCP/workspaces/FocusRead-104d4296e8fa/result-bundles/` |
| Fixtures | Generated 25k-word TXT, generated 18-page native-text PDF, `jane-austen_pride-and-prejudice.epub`, generated reader text fixtures |

## Benchmark Coverage

Permanent benchmark infrastructure added:

- `FocusReadTests/ImportPipelinePerformanceTests.swift`
- `FocusReadTests/ReaderPerformanceTests.swift`
- `FocusReadTests/PerformanceBenchmarkFixtures.swift`
- `FocusReadUITests/FocusReadLaunchPerformanceTests.swift`
- `FocusRead/Services/FocusReadBenchmarkSignposts.swift`

Production signposts are gated by `FOCUSREAD_BENCHMARK_SIGNPOSTS=1` or `-FocusReadBenchmarks`, so normal app launches avoid benchmark logging.

## Measured Metrics

Unit performance suite command:

```sh
xcodebuild test \
  -project FocusRead.xcodeproj \
  -scheme FocusRead \
  -destination 'platform=iOS Simulator,id=9EF26532-319C-4E6B-BE6B-01FFB7A2BB16' \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:FocusReadTests/ReaderPerformanceTests \
  -only-testing:FocusReadTests/ImportPipelinePerformanceTests
```

Result: 7 passed, 0 failed.

| Area | Test | Mean wall/signpost time | CPU time | Peak memory |
| --- | --- | ---: | ---: | ---: |
| EPUB import to readable words | `testEPUBImportToReadableWordsPerformance` | 0.832s signpost, 1.202s total | 1.219s | 119.5 MB |
| PDF import to readable words | `testPDFImportToReadableWordsPerformance` | 0.049s signpost, 0.064s total | 0.066s | 105.3 MB |
| TXT import to readable words | `testTXTImportToReadableWordsPerformance` | 0.006s signpost, 0.084s total | 0.084s | 108.8 MB |
| 120k-word tokenization | `testLargeDocumentTokenizationPerformance` | 0.364s signpost, 0.361s total | 0.362s | 136.3 MB |
| Reader open from 80k-word document | `testReaderOpenFromImportedDocumentPerformance` | 0.241s total | 0.243s | 123.3 MB |
| 5k high-WPM state advances | `testHighWPMPlaybackStateAdvancementPerformance` | 0.001s total | 0.004s | 118.4 MB |
| Rapid speed changes | `testRapidPlaybackSpeedChangesPerformance` | <0.001s total | 0.001s | 110.8 MB |

UI performance:

| Area | Test | Mean metric |
| --- | --- | ---: |
| Cold-ish launch to first responsive frame | `testColdLaunchPerformance` | 3.019s |
| Discover -> Library -> My Stats -> Settings -> Discover navigation | `testCoreTabNavigationResponsiveness` | 11.466s total measured loop |
| Navigation app CPU | `testCoreTabNavigationResponsiveness` | 1.531s |
| Navigation absolute memory | `testCoreTabNavigationResponsiveness` | 124.5 MB |
| Navigation peak memory | `testCoreTabNavigationResponsiveness` | 146.4 MB |

Notes:

- XCTest launch metrics repeat the app launch several times. The UI tests are intentionally deterministic but still slow.
- `testColdLaunchPerformance` currently uses `-ApplePersistenceIgnoreState YES` plus benchmark env, not a full app uninstall. A future device/simulator script should pair this with `simctl uninstall` for a stricter cold launch.
- `XCTHitchMetric` is included where available for navigation. No dedicated animation-hitch bottleneck was isolated in this first pass.

## First-Run vs Cached-Run

Current coverage:

- First-run style launch: `testColdLaunchPerformance` with ignored persistent state and onboarding bypassed by `FOCUSREAD_SKIP_ONBOARDING=1`.
- Cached app state: warm launch test exists in `FocusReadLaunchPerformanceTests`, but it was not rerun to completion after narrowing the UI suite because launch metric repetitions are slow. It should be run separately before using warm launch numbers for regression gates.
- Reopening same book/cache effectiveness: not yet permanently covered. Add a seeded library fixture and measure `SavedReadMapper.importedDocument(from:)`, tokenization on resume, cover cache behavior, and launch-after-termination.

## Memory / CPU Observations

- Import and tokenization are CPU-bound and stable at this fixture size.
- Peak process memory during large tokenization is about 136 MB in Debug on simulator.
- UI navigation sits around 124.5 MB absolute / 146.4 MB peak.
- EPUB import has the highest measured CPU cost in the current suite: about 1.2s CPU for Pride and Prejudice.
- No retain-cycle or leak conclusion should be drawn yet; run Instruments Leaks/Allocations on long reader playback before making that claim.

## SwiftUI / Main-Thread Findings

- The UI navigation benchmark exercises Discover, Library, My Stats, and Settings tab transitions. The measured loop is dominated by XCTest waiting and SwiftUI screen realization, not pure app work.
- Discover is the highest-risk SwiftUI surface because it includes network-fed content, cover loading, pagination, and rich cards.
- Library and Stats should get more targeted tests with seeded many-book data. The current benchmark only proves that tab navigation remains measurable and repeatable.
- Main-thread blocking was not conclusively isolated in this pass. Use Time Profiler and Main Thread Checker style inspection around Discover first render and library search.

## Ranked Bottlenecks

1. **Launch/first interactive frame: Medium-high severity**
   - Current cold-ish launch is 3.019s in Debug simulator. The app now has onboarding, cloud sync setup, recap store, Discover-first UI, localization/theme refresh, and widget/shared state. This is the most user-visible latency.

2. **EPUB import: Medium severity**
   - EPUB import to readable words is 1.202s total / 0.832s import signpost for a large book. This is acceptable, but it is the slowest measured import path and should be watched with larger EPUBs.

3. **Discover/library UI realization: Medium severity**
   - Navigation loop is 11.466s under XCTest. Some of this is automation overhead, but Discover and Library are complex enough to deserve targeted Time Profiler and hitch runs.

4. **Large tokenization: Low-medium severity**
   - 120k words tokenize in 0.364s. This is good, but it is synchronous and can still matter if performed on the main actor during reader open.

5. **Playback state advancement and speed changes: Low severity**
   - State-only reader operations are effectively negligible. Do not optimize these until visual playback/hitches prove otherwise.

## Recommendations

| Recommendation | Expected impact | Merge target |
| --- | --- | --- |
| Keep gated signposts for `DocumentImport` and `TextTokenization`. | Enables low-noise XCTest/Instruments timing without user-facing logging. | Main |
| Keep unit performance tests for import, tokenization, reader open, and playback state. | Gives objective regression coverage for core latency. | Main or benchmark target |
| Keep UI launch/navigation tests, but run launch tests selectively in CI/nightly. | Captures user-perceived launch regressions. | Benchmark-only or nightly CI |
| Add a seeded-library benchmark fixture with 100/500/1000 saved reads. | Quantifies Library scrolling/search/cover loading. | Benchmark branch first |
| Add strict cold/warm launch helper script using `simctl uninstall`, install, launch, and `xcodebuild test`. | Separates first-run from cached-run performance. | Benchmark branch |
| Profile Discover first render with Time Profiler and Animation Hitches. | Likely best next source of UI responsiveness improvements. | Benchmark branch first |
| Move any synchronous large-tokenization call off the main actor only if reader-open UI traces show blocking. | Avoids premature architecture churn. | Only after evidence |

## Not Worth Touching Yet

- `ReadingSession.advance()` and speed changes are already tiny.
- TXT native extraction is effectively instantaneous relative to tokenization.
- Generated native-text PDF extraction is fast for this fixture; scanned/OCR PDFs need separate measurement before any OCR optimization.
- Micro-optimizing token object field assignment is not justified by current numbers.

## Complexity / Over-Engineering Watchlist

- Avoid adding permanent debug overlays or benchmark-only UI inside normal screens.
- Avoid broad caching layers before measuring reopen and library-scale behavior.
- Keep signposts centralized and gated. Do not scatter unconditional `os_log` calls.
- UI benchmarks should prefer stable app flows over fragile text matching inside content feeds.

## Instruments Plan

Run these manually from the corrected perf branch:

1. App Launch template: benchmark launch with onboarding skipped and again with a true clean install.
2. Time Profiler: Discover first render, Library search with seeded reads, EPUB import.
3. Allocations: 10-minute reader playback, large EPUB import, large PDF import.
4. Leaks: long reader playback with repeated open/close.
5. Animation Hitches: tab navigation, Library scroll, Discover scroll/pagination, reader playback at high WPM.

Keep `.trace` files outside the repo.
