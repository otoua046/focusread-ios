#!/usr/bin/env node
const { execFileSync } = require("child_process");
const path = process.argv[2];

if (!path) {
  console.error("Usage: extract-xcresult-metrics.js <bundle.xcresult>");
  process.exit(2);
}

const raw = execFileSync("xcrun", [
  "xcresulttool",
  "get",
  "test-results",
  "metrics",
  "--path",
  path,
  "--compact"
], { encoding: "utf8" });

const data = JSON.parse(raw);
for (const test of data) {
  console.log(test.testIdentifier);
  for (const run of test.testRuns) {
    const device = run.device;
    console.log(`  device: ${device.deviceName} (${device.deviceId})`);
    for (const metric of run.metrics) {
      const values = metric.measurements;
      if (!values || values.length === 0) continue;
      const average = values.reduce((sum, value) => sum + value, 0) / values.length;
      console.log(`  ${metric.displayName}: ${average.toFixed(3)} ${metric.unitOfMeasurement}`);
    }
  }
}
