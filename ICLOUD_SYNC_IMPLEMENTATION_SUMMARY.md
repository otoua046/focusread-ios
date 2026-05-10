# iCloud Sync Implementation Summary

iCloud sync is currently implemented as a metadata-first, local-first architecture, but CloudKit is intentionally disabled for normal dev builds. Real CloudKit initialization is gated behind FocusReadCloudKitEnabled and should only be enabled in an iCloud-capable build configuration with proper entitlements/provisioning.

Normal dev builds should show iCloud Sync as unavailable for this build. A separate CloudKit-enabled dev/test build should be used for real-device sync testing. The app must never initialize CKContainer or CloudKit services unless the feature flag and entitlements are valid.
