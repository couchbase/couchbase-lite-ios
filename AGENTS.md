# Couchbase Lite for Apple Platforms

Embedded NoSQL database for iOS and macOS. The codebase is an Objective-C core with a Swift wrapper built on LiteCore.

## Repository Layout

This repo expects a sibling checkout:

```text
<workspace>/
├── couchbase-lite-ios/      # Community Edition repo
└── couchbase-lite-ios-ee/   # Enterprise Edition repo
```

Key paths in `couchbase-lite-ios/`:
- `CouchbaseLite.xcodeproj` for schemes and targets
- `Objective-C/` for the primary implementation and public Obj-C API
- `Swift/` for the Swift wrapper layer
- `Tests/` and `Tests/Extensions/` for tests and test-only extensions
- `xcconfigs/` for build settings
- `Scripts/` for packaging, CI, and release automation
- `vendor/couchbase-lite-core/` for LiteCore
- `vendor/couchbase-lite-core-EE` as a symlink into the EE sibling repo

Key EE paths in `../couchbase-lite-ios-ee/`:
- `Sources/Objective-C/`
- `Sources/Swift/`
- `couchbase-lite-core-EE/`

- Primary schemes: `CBL_ObjC`, `CBL_Swift`, `CBL_EE_ObjC`, `CBL_EE_Swift`
- Common iOS app-hosted test schemes: `CBL_ObjC_Tests_iOS_App`, `CBL_Swift_Tests_iOS_App`, `CBL_EE_ObjC_Tests_iOS_App`, `CBL_EE_Swift_Tests_iOS_App`

## Architecture Rules

- Community Edition code must not depend on Enterprise Edition code.
- Enterprise Edition code may extend Community Edition behavior via EE sources or `COUCHBASE_ENTERPRISE` guards.
- Swift APIs mirror Obj-C APIs, so public API changes usually require updates in both layers.
- Swift-to-Obj-C bridging is controlled by `Swift/CouchbaseLiteSwift.private.modulemap` and `../couchbase-lite-ios-ee/Sources/Swift/CouchbaseLiteSwift.private.modulemap`.
- If a new Obj-C header must be visible to Swift, update the appropriate private module map.
- Public Obj-C exported symbols are defined from `Objective-C/Exports/CBL.txt` and `Objective-C/Exports/CBL_EE.txt`.

## Agent Workflow

- Plan first before making changes unless the task is trivial.
- Keep the plan short and concrete so the developer can review it quickly.
- Prefer Xcode MCP or other IDE-integrated Xcode tools when available.
- If Xcode MCP is not available, confirm with the developer whether they want to validate in Xcode, use `xcodebuild`, or run the tests themselves.
- After making changes, use the narrowest reasonable validation.

## Guardrails

- Do not hand-edit `CouchbaseLite.xcodeproj/project.pbxproj`.
- If a task requires new files or changes project membership, stop and ask the developer to do that in Xcode.
- Editing existing source files and `xcconfigs/*.xcconfig` is fine.
- Do not edit generated export files in `Objective-C/Exports/Generated/` directly. Update the templates and run `Objective-C/Exports/generate_exports.sh` instead.
- For packaging or release tasks, use the existing scripts in `Scripts/` rather than inventing new archive commands.

## Done Criteria

- Summarize what changed.
- Mention assumptions made and exactly what was built or tested.
- Call out anything not verified locally.

## Build and Test

Useful fallback commands:

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
xcodebuild clean test \
  -project CouchbaseLite.xcodeproj \
  -scheme CBL_EE_Swift_Tests_iOS_App \
  -sdk iphonesimulator \
  -destination "platform=iOS Simulator,name=$TEST_SIMULATOR"
```

Some tests rely on extension artifacts under `Tests/Extensions/`. 
See `Tests/Extensions/README.md` and use `Scripts/download_vector_search_extension.sh` if needed.

Validation:

- Validate the layer you changed.
- Validate both Obj-C and Swift for public API changes.
- Use EE schemes for EE-only changes.
