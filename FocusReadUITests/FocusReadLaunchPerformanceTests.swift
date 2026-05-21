import XCTest

@MainActor
final class FocusReadLaunchPerformanceTests: XCTestCase {
    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        false
    }

    func testColdLaunchPerformance() {
        let app = benchmarkApplication(resetPersistentState: true)

        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)]) {
            app.launch()
            XCTAssertTrue(app.buttons["Library"].waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    func testWarmLaunchPerformance() {
        let app = benchmarkApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Library"].waitForExistence(timeout: 5))
        app.terminate()

        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true), XCTMemoryMetric(application: app), XCTCPUMetric(application: app)]) {
            app.launch()
            XCTAssertTrue(app.buttons["Library"].waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    func testCoreTabNavigationResponsiveness() {
        let app = benchmarkApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Library"].waitForExistence(timeout: 5))

        var metrics: [any XCTMetric] = [
            XCTClockMetric(),
            XCTMemoryMetric(application: app),
            XCTCPUMetric(application: app)
        ]
        if #available(iOS 26.0, *) {
            metrics.append(XCTHitchMetric(application: app))
        }

        measure(metrics: metrics) {
            app.buttons["Library"].tap()
            XCTAssertTrue(app.buttons["My Stats"].waitForExistence(timeout: 5))
            app.buttons["My Stats"].tap()
            XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 5))
            app.buttons["Settings"].tap()
            XCTAssertTrue(app.buttons["Discover"].waitForExistence(timeout: 5))
            app.buttons["Discover"].tap()
            XCTAssertTrue(app.buttons["Library"].waitForExistence(timeout: 5))
        }
    }

    private func benchmarkApplication(resetPersistentState: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-FocusReadBenchmarks"]
        if resetPersistentState {
            app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        }
        app.launchEnvironment["FOCUSREAD_BENCHMARK_SIGNPOSTS"] = "1"
        app.launchEnvironment["FOCUSREAD_SKIP_ONBOARDING"] = "1"
        return app
    }
}
