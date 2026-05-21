# FocusRead Expanded Benchmark Report

Branch: `perf/benchmark-suite`
Base: `codex/liquid-glass-controls` at `782969b`
Date: 2026-05-21

## Environment

| Field | Value |
| --- | --- |
| Simulator | iPhone 17 Pro Max Simulator |
| Simulator ID | `9EF26532-319C-4E6B-BE6B-01FFB7A2BB16` |
| iOS runtime | 26.2 (`23C54`) |
| Device attempt | `tk1`, iOS 26.4.2, id `00008150-000835341482401C` |
| Build configurations | Debug simulator, Release simulator with `ENABLE_TESTABILITY=YES` |
| Fixture set | Generated text, generated native PDF, generated image-only scanned PDF, Pride and Prejudice EPUB, seeded 100/500/1000-read Library data, synthetic Discover sections |
| Result artifacts | `.xcresult`, logs, TSVs, and extracted metric summaries in ignored `benchmarks/results/` |
| Instruments | App Launch template was available; a local Release trace was attempted under ignored `benchmarks/traces/`, but the CLI recording did not stop cleanly on the requested 15s window, so no trace-derived metrics are reported. |

Primary commands:

```sh
xcodebuild test -project FocusRead.xcodeproj -scheme FocusRead -destination 'platform=iOS Simulator,id=9EF26532-319C-4E6B-BE6B-01FFB7A2BB16' CODE_SIGNING_ALLOWED=NO -only-testing:FocusReadTests/ReaderPerformanceTests -only-testing:FocusReadTests/ImportPipelinePerformanceTests
xcodebuild test -project FocusRead.xcodeproj -scheme FocusRead -configuration Release -destination 'platform=iOS Simulator,id=9EF26532-319C-4E6B-BE6B-01FFB7A2BB16' CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES -only-testing:FocusReadTests/ReaderPerformanceTests -only-testing:FocusReadTests/ImportPipelinePerformanceTests -only-testing:FocusReadTests/LibraryScalePerformanceTests -only-testing:FocusReadTests/DiscoverPerformanceTests -only-testing:FocusReadTests/OCRImportPerformanceTests
benchmarks/scripts/strict-launch-benchmark.sh Debug
benchmarks/scripts/strict-launch-benchmark.sh Release
```

## Release vs Debug

| Area | Debug simulator | Release simulator | Observation |
| --- | ---: | ---: | --- |
| EPUB import, total wall | 1.202s | 0.904s | Release is about 25% faster. EPUB remains acceptable but should stay in regression coverage. |
| EPUB import signpost | 0.832s | 0.581s | Extract/cleanup work improves materially in Release. |
| 120k-word tokenization | 0.364s | 0.308s | Fast in both builds. Not a current optimization target. |
| Reader open, 80k-word document | 0.241s | 0.205s | Good. Watch only if UI traces show synchronous main-thread stalls. |
| Native PDF import | 0.064s | 0.065s | Noise-level difference; not worth touching. |
| TXT import | 0.084s | 0.074s | Fast. |
| Scanned PDF OCR, 1 page | 1.338s | 3.332s | Inconclusive cross-build comparison; Vision/OCR behavior varies by simulator and warm state. It is still the heaviest import path. |
| Launch first responsive frame | 3.019s Debug baseline | 4.990s average, values 2.02s, 2.13s, 2.21s, 6.96s, 11.63s | Release launch is high variance and remains the top risk. |

## Strict Launch

`strict-launch-benchmark.sh` uses `simctl uninstall`, `install`, `terminate`, and `launch` with benchmark flags. This measures `simctl launch` command elapsed time, not first interactive frame.

| Scenario | Debug | Release run 1 | Release rerun | Interpretation |
| --- | ---: | ---: | ---: | --- |
| True cold clean install | 0.340s | 7.019s | 7.830s | Release clean launch repeatedly has a long simulator command elapsed path. Needs App Launch Instruments before optimizing. |
| Cold launch with existing data | 0.334s | 0.361s | 8.277s | Mixed. Simulator state is noisy; treat as a risk signal, not a final metric. |
| Warm launch / terminate running process | 0.570s | 1.991s | 0.506s | Variable, likely affected by simulator/service state. |
| Launch after force-quit | 0.284s | 0.355s | 0.294s | Stable and low by this process-spawn metric. |

## Library Scale

Deterministic seeded `SavedReads.json` fixtures were generated in tests for 100, 500, and 1000 saved reads. These measure model hydration/search/sort, not full SwiftUI grid scrolling yet.

| Test | Debug wall | Release wall | Release peak memory |
| --- | ---: | ---: | ---: |
| Hydrate 100 saved reads | 0.006s | 0.007s | 181.3 MB |
| Hydrate 500 saved reads | 0.028s | 0.026s | 183.4 MB |
| Hydrate 1000 saved reads | 0.055s | 0.056s | 185.1 MB |
| Search/filter/sort 1000 saved reads | 0.032s | 0.025s | 183.0 MB |

Finding: Library model work is good at 1000 items. The remaining unknown is visible SwiftUI scrolling and thumbnail/cover loading with many actual images.

## Discover

Network-independent Discover coverage now measures seeded first render setup, large fixture curation, related-book scoring, and trusted fast search.

| Test | Debug wall | Release wall | Release peak memory |
| --- | ---: | ---: | ---: |
| ViewModel seeded first render | 0.028s | 0.025s | 177.4 MB |
| Curated presentation for 1000 books | 0.137s | 0.130s | 179.2 MB |
| Related books from large fixture | ~0.000s | ~0.000s | 177.9 MB |
| Trusted fast search | 0.005s | 0.005s | 177.5 MB |

Finding: deterministic Discover model operations are not the bottleneck. The unmeasured user-visible risks are image loading, real pagination, cache misses, and SwiftUI scroll hitches. Those need Time Profiler/Animation Hitches traces, not speculative code changes.

No Time Profiler or Animation Hitches metrics are reported here. The simulator and XCTest runs identify where those traces should focus: Release launch, Discover image/pagination scrolling, and Library thumbnail-heavy scrolling.

## OCR / Scanned PDF

The prior native-text PDF fixture was too easy. The suite now creates an image-only scanned PDF and forces the PDF import path through OCR.

| Metric | Debug | Release |
| --- | ---: | ---: |
| One-page scanned PDF import wall time | 1.338s | 3.332s |
| CPU time | 2.877s | 2.814s |
| Peak memory | 196.6 MB | 212.5 MB |

Finding: OCR is the heaviest import path and has elevated memory. Because OCR is inherently expensive, the first product question is whether progress UI and cancellation stay responsive, not whether OCR can be micro-optimized.

## Main-Thread Audit

| Area | Current path | Finding |
| --- | --- | --- |
| EPUB parsing | `DocumentImportViewModel` calls `DocumentImportWorker` actor, which calls `EPUBTextExtractor` synchronously inside async import work. | Not MainActor in normal UI import flow. Work can still occupy the import actor for about 0.9s Release on the EPUB fixture. |
| PDF extraction | Same worker actor path, PDFKit native extraction loops pages synchronously. | Native text PDF is fast in current fixture. Larger PDFs need page-count scale coverage. |
| OCR | Worker actor path; Vision `VNImageRequestHandler.perform` is synchronous per page. | Not MainActor in normal UI import flow, but it is long-running and memory-heavy. Keep progress/cancellation responsive. |
| Tokenization | `TextTokenizer` is synchronous; reader view model is `@MainActor`. | 120k words is 0.308s Release. Only move off-main if first-word/reader-open traces prove a visible stall. |
| Saved library hydration | File load uses `ReadingHistoryFileLoader`, then applies results on `MainActor`; search/sort is `LibraryViewModel` on `MainActor`. | 1000 reads is fine. Watch larger libraries or thumbnail-heavy grids. |
| Discover data loading | `DiscoverViewModel` is `@MainActor`; service/network/cache work is actor/async. Applying sections and curation are currently fast. | Main risk is SwiftUI rendering plus async cover loads, not model curation. |
| Cover generation/loading | Library thumbnails use `ThumbnailGeneratorService` actor. Discover covers load through `DiscoverCoverImageCache` in `.task`. | No evidence of model-side blocking. Need scroll/hitch traces with real covers. |

## Real Device

The connected device was detected:

| Field | Value |
| --- | --- |
| Name | `tk1` |
| iOS | 26.4.2 |
| ID | `00008150-000835341482401C` |

Attempted Release XCTest runs failed before execution because the scheme builds `FocusReadUITests`, and the UI test runner bundle `com.otoua046.app.uitests.xctrunner` had no matching iOS Development provisioning profile. `-skip-testing:FocusReadUITests` did not avoid building the target. No real-device performance numbers are claimed.

## Top 5 Risks Before TestFlight

1. Launch/first interactive frame: Release simulator launch averaged 4.990s with severe variance.
2. OCR/scanned PDF import: heaviest path, 196-213 MB peak memory in simulator.
3. Discover real-world UI: deterministic model work is fine, but cover loading, pagination, and scroll hitches remain untraced.
4. Large real PDFs/EPUBs: current EPUB is acceptable, but larger chapter structures and PDFs need broader fixtures.
5. Device-grade validation gap: connected device is visible, but signing blocks XCTest performance runs.

## Not Worth Optimizing Now

1. Playback state advancement and rapid speed changes.
2. TXT import.
3. Native-text PDF import at current fixture size.
4. Library model search/sort at 1000 saved reads.
5. Discover trusted search, related-book scoring, and curated presentation model work.

## Merge / Keep / Delete

| Item | Recommendation |
| --- | --- |
| `benchmarks/README.md`, dated reports, scripts, fixture docs | Merge to main. This is long-term engineering infrastructure. |
| Unit performance tests for import, reader, Library scale, Discover fixtures, OCR | Merge to main or keep in a dedicated benchmark test plan. |
| Gated signposts for `DocumentImport` and `TextTokenization` | Merge to main; they are low overhead and disabled by default. |
| UI launch/navigation tests | Merge only if run selectively; they are valuable but slow/noisy for every PR. |
| Strict launch script | Keep in `benchmarks/scripts`; do not put in production app code. |
| `benchmarks/results/`, `.xcresult`, `.trace`, local logs | Keep out of git. Delete or archive locally after reports are updated. |
| Benchmark-only onboarding bypass env | Acceptable for UI automation if kept gated to env/launch args and not user-visible. |

## Next Measurements

1. Run App Launch Instruments on Release simulator and real device after signing is fixed.
2. Add a device-capable benchmark scheme/test plan that does not require signing the UI runner for unit-only device performance.
3. Add Library SwiftUI scroll and cover-loading benchmarks using seeded thumbnails.
4. Add Discover Animation Hitches traces for first render, pagination, and image cache miss/hit.
5. Add larger scanned PDF and large-PDF page-count fixtures, keeping generated files outside git.
