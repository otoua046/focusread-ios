# FocusRead Benchmarks

This directory stores durable benchmark infrastructure and reports. Keep reports, scripts, and lightweight fixture documentation in git. Keep bulky or machine-specific profiling output out of git.

## Structure

- `reports/`: dated benchmark reports.
- `scripts/`: repeatable benchmark commands and result extraction helpers.
- `fixtures/`: notes or lightweight reusable benchmark fixture data.
- `traces/`: local Instruments traces. Ignored by git.
- `results/`: local `.xcresult` bundles, logs, and generated JSON summaries. Ignored by git.

## Benchmark History

| Date | Branch/commit | Build | Device | Launch | EPUB import | Tokenization | Notes |
| --- | --- | --- | --- | ---: | ---: | ---: | --- |
| 2026-05-20 | `perf/benchmark-suite` / `782969b` | Debug simulator | iPhone 17 Pro Max Simulator, iOS 26.2 | 3.019s cold-ish first responsive frame | 1.202s total, 0.832s signpost | 0.364s for 120k words | Initial benchmark baseline on liquid-glass branch. Core reader state is fast; launch is highest visible risk. |
| 2026-05-21 | `perf/benchmark-suite` / `782969b` | Debug simulator | iPhone 17 Pro Max Simulator, iOS 26.2 | 3.019s first responsive frame; strict launch 0.284-0.570s simctl command elapsed | 1.202s total, 0.832s signpost | 0.364s for 120k words | Added Library scale, Discover fixture, scanned-PDF OCR, strict launch harness, and benchmark storage layout. |
| 2026-05-21 | `perf/benchmark-suite` / `782969b` | Release simulator with `ENABLE_TESTABILITY=YES` | iPhone 17 Pro Max Simulator, iOS 26.2 | 4.990s first responsive frame, high variance; strict cold/existing-data simctl launch 7-8s reproduced | 0.904s total, 0.581s signpost | 0.308s for 120k words | Release improves core pipeline metrics but launch variance remains the top TestFlight risk. Real-device run blocked by XCTest runner provisioning. |

## Running Unit Benchmarks

```sh
benchmarks/scripts/run-xctest-benchmarks.sh Debug
benchmarks/scripts/run-xctest-benchmarks.sh Release
```

The script writes `.xcresult` bundles and metric summaries into `benchmarks/results/`, which is ignored by git. Release runs set `ENABLE_TESTABILITY=YES` because the benchmark tests use `@testable import FocusRead`.

By default the scripts look for an available `iPhone 17 Pro Max` simulator. Override with `SIMULATOR_ID=<udid>` or `SIMULATOR_NAME="<name>"` on machines with different simulator sets.

## Running Strict Launch Benchmarks

```sh
benchmarks/scripts/strict-launch-benchmark.sh Debug
benchmarks/scripts/strict-launch-benchmark.sh Release
```

This script uses `simctl uninstall`, `install`, and `launch` to separate clean install, existing-data cold launch, warm launch, and force-quit launch scenarios. Treat these as local measurements because simulator load and host state affect results.

The strict launch script measures `simctl launch` command elapsed time. It is useful for comparing launch state scenarios, but it is not the same metric as first interactive frame. Pair it with `FocusReadLaunchPerformanceTests/testColdLaunchPerformance` before making user-facing launch claims.

## Running UI Launch Benchmarks

The `FocusReadUITests` target is skipped in the shared scheme so ordinary `xcodebuild test` runs do not pick up slow launch/navigation performance tests. Run UI performance tests explicitly for nightly or release-readiness checks:

```sh
xcodebuild test \
  -project FocusRead.xcodeproj \
  -scheme FocusRead \
  -destination "platform=iOS Simulator,id=${SIMULATOR_ID}" \
  -only-testing:FocusReadUITests/FocusReadLaunchPerformanceTests
```

Use `FOCUSREAD_SKIP_ONBOARDING=1`, `FOCUSREAD_BENCHMARK_SIGNPOSTS=1`, and `-FocusReadBenchmarks` only for benchmark runs. They are not user-facing app controls.

## Extracting Metrics

```sh
benchmarks/scripts/extract-xcresult-metrics.js benchmarks/results/some-result.xcresult
```

Reports should always record:

- branch and commit
- device or simulator model
- iOS version
- build configuration
- fixture set
- command used
- exact measured metrics
- limitations and inconclusive areas

## Hygiene

Do not commit:

- `.trace` files
- `.xcresult` bundles
- Instruments recordings
- temporary logs
- large generated artifacts

Do not add benchmark-only app UI. Keep signposts gated and low noise.
