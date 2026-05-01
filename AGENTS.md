# Couchbase Lite for Apple Platforms

Embedded NoSQL database for iOS and macOS. The codebase is an Objective-C core with a Swift wrapper built on LiteCore.

## Repository Layout

This repo expects the Community and Enterprise repos to be sibling checkouts:

```text
<workspace>/
├── couchbase-lite-ios/      # Community Edition repo
└── couchbase-lite-ios-ee/   # Enterprise Edition repo
```

Key paths in `couchbase-lite-ios/`:
- `CouchbaseLite.xcodeproj` for schemes and targets
- `Objective-C/` for the main implementation and public Obj-C API
- `Swift/` for the Swift wrapper layer
- `Tests/` and `Tests/Extensions/` for tests
- `xcconfigs/` for build settings
- `Scripts/` for packaging, CI, and release automation
- `vendor/couchbase-lite-core/` for LiteCore
- `vendor/couchbase-lite-core-EE` symlinked to the EE sibling repo

Key EE paths in `../couchbase-lite-ios-ee/`:
- `Sources/Objective-C/`
- `Sources/Swift/`
- `couchbase-lite-core-EE/`

Primary Xcode schemes:
- `CBL_ObjC` for Objective-C Community Edition
- `CBL_Swift` for Swift Community Edition
- `CBL_EE_ObjC` for Objective-C Enterprise Edition
- `CBL_EE_Swift` for Swift Enterprise Edition

iOS app-hosted test schemes:
- `CBL_ObjC_Tests_iOS_App` for Objective-C Community Edition tests
- `CBL_Swift_Tests_iOS_App` for Swift Community Edition tests
- `CBL_EE_ObjC_Tests_iOS_App` for Objective-C Enterprise Edition tests
- `CBL_EE_Swift_Tests_iOS_App` for Swift Enterprise Edition tests

## Architecture Notes

- Community Edition code must not depend on Enterprise Edition code.
- Enterprise Edition code may extend Community Edition behavior through EE sources or `COUCHBASE_ENTERPRISE` guards.
- Swift APIs mirror Obj-C APIs; public API changes usually require updates in both layers.
- Swift-to-Obj-C bridging is controlled by `Swift/CouchbaseLiteSwift.private.modulemap` and `../couchbase-lite-ios-ee/Sources/Swift/CouchbaseLiteSwift.private.modulemap`.
- If a new Obj-C header must be visible to Swift, update the appropriate private module map.
- Public Obj-C exported symbols are defined by `Objective-C/Exports/CBL.txt` and `Objective-C/Exports/CBL_EE.txt`.

## Guardrails

- Do not hand-edit `CouchbaseLite.xcodeproj/project.pbxproj`.
- If a task requires new files or project membership changes, ask the developer to make them in Xcode.
- Do not edit generated export files in `Objective-C/Exports/Generated/` directly. Update the templates and run `Objective-C/Exports/generate_exports.sh` instead.

## Build and Test

Use `xcodebuild` for builds and tests. After changes, verify the relevant scheme builds and run the narrowest applicable tests. Prefer the EE scheme, using the Obj-C or Swift variant that best matches the change.

```bash
# List available schemes and targets
xcodebuild -list -project CouchbaseLite.xcodeproj

# Run EE Swift macOS tests
xcodebuild test \
  -project CouchbaseLite.xcodeproj \
  -scheme CBL_EE_Swift \
  -destination "platform=macOS"

# Run EE Swift iOS app-hosted tests on an available simulator
TEST_SIMULATOR=$(xcrun simctl list devices available | grep -E "iPhone.*" | head -n 1 | sed 's/^[[:space:]]*//; s/ (.*//')
xcodebuild test \
  -project CouchbaseLite.xcodeproj \
  -scheme CBL_EE_Swift_Tests_iOS_App \
  -sdk iphonesimulator \
  -destination "platform=iOS Simulator,name=$TEST_SIMULATOR"
```
