# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Common developer commands

Environment variables used by the commands below:

```bash
export PROJ="IconFinder.xcodeproj"
export SCHEME="IconFinder"
export DERIVED=".build" # repo-local DerivedData
```

### List schemes and targets

```bash
xcodebuild -list -project "$PROJ"
```

### Build (Debug)

```bash
xcodebuild -project "$PROJ" -scheme "$SCHEME" -configuration Debug -derivedDataPath "$DERIVED" -quiet build
```

### Build (Release)

```bash
xcodebuild -project "$PROJ" -scheme "$SCHEME" -configuration Release -derivedDataPath "$DERIVED" -quiet build
```

### Run the built app (after a Debug build)

```bash
APP_NAME="$(xcodebuild -project "$PROJ" -scheme "$SCHEME" -configuration Debug -showBuildSettings | awk -F= '/FULL_PRODUCT_NAME/ {gsub(/[[:space:]]/," ");print $2}' | tail -1)"; open "$DERIVED/Build/Products/Debug/$APP_NAME"
```

### Clean

```bash
xcodebuild -project "$PROJ" -scheme "$SCHEME" -configuration Debug -derivedDataPath "$DERIVED" -quiet clean
rm -rf "$DERIVED"
```

### Static analysis (Clang analyzer)

```bash
xcodebuild -project "$PROJ" -scheme "$SCHEME" -configuration Debug -derivedDataPath "$DERIVED" -quiet clean analyze
```

### Archive (Release)

```bash
xcodebuild -project "$PROJ" -scheme "$SCHEME" -configuration Release -archivePath "$DERIVED/IconFinder.xcarchive" -quiet archive
```

### Tests

There are no test targets in this repository; single-test or test-suite commands do not apply.

## High-level architecture overview

- App lifecycle and controller
  - `JRAppDelegate` is the primary coordinator. On launch it loads previously cached image paths from `~/Library/Application Support/IconFinder/imagePaths.plist` or kicks off a fresh scan.
  - Maintains `imagePaths` (all discovered images), `filters` (selected via `NSSegmentedControl`), and exposes `filteredImagePaths` via an `NSPredicate`. KVO is used so UI updates when filters or results change.

- Image discovery pipeline
  - Uses `NSTask` to invoke `/usr/bin/find` across the filesystem to locate common image types (`jpeg`, `jpg`, `gif`, `png`, `icns`, `tiff`, `pdf`).
  - Streams `stdout` through an `NSPipe` and subscribes to `NSFileHandleReadCompletionNotification` to append discovered paths incrementally.
  - Writes the final list to `~/Library/Application Support/IconFinder/imagePaths.plist` for fast reloads on subsequent launches.
  - A Stop action terminates the running `NSTask` cleanly; a Remove Image Cache action deletes the plist and triggers a rescan.

- UI composition
  - `MainMenu.xib` defines the main window and connects outlets/actions on `JRAppDelegate`, including the segmented control used for filtering by file extension.
  - The grid is an `NSCollectionView` subclass (`JRCollectionView`). It handles double-click (`mouseDown` with `clickCount == 2`) to open the selected file via `NSWorkspace`.
  - `JRImageCollectionItemView` draws a subtle selection/border treatment. `JRImageCollectionViewItemViewController` is the item controller for per-cell presentation. An item XIB (`JRImageCollectionViewItemViewController.xib`) defines the cell UI.

- Data flow
  - `find` output → `imagePaths` (mutable backing store) → `filteredImagePaths` (predicate-applied) → collection view items → double-click opens file in the default app.

- Notable project settings (from `project.pbxproj`)
  - `MACOSX_DEPLOYMENT_TARGET`: 13.5
  - `MARKETING_VERSION`: 2.0
  - `CURRENT_PROJECT_VERSION`: 100
  - `CLANG_USE_OPTIMIZATION_PROFILE`: YES (`OptimizationProfiles/` exists to support PGO)

## Usage notes

- Full Disk Access on modern macOS
  - Scanning the root volume (`/`) may be restricted. When debugging from the CLI or Xcode, grant Full Disk Access to the launching app (e.g., Terminal or Xcode) to ensure the `NSTask`-based search can read all directories.

- Long-running search and cancellation
  - The UI’s Stop control cancels the active `NSTask`. After stopping, filters and counts update and you can trigger a new scan.

- Cache location and reset
  - Cache file: `~/Library/Application Support/IconFinder/imagePaths.plist`
  - Reset from the app’s UI (Remove Image Cache). From the CLI during development:

```bash
rm -f "$HOME/Library/Application Support/IconFinder/imagePaths.plist"
```

### Default scan behavior and Settings

- On first launch, scanning uses Spotlight (fast) and starts from the entire root volume (`/`). Results appear incrementally.
- Defaults:
  - Deep Scan: OFF (use Spotlight; turn ON to walk the filesystem)
  - Hide Duplicates: OFF (turn ON to hide exact duplicates via SHA-256)
  - Exclude External Volumes: ON (external volumes are skipped unless you turn this OFF)
  - Exclude from Scan list: empty (add paths you want to omit, e.g., very large or sensitive directories)
- Settings… (⌘,):
  - Enable Deep Scan: switches from Spotlight to a full filesystem walk
  - Hide Duplicates: hides exact duplicates using cached SHA-256 hashes
  - Exclude External Volumes: when ON, paths under `/Volumes` are not scanned
  - Exclude from Scan: add/remove specific directories to omit from scanning

Notes:
- For Deep Scan over system-protected areas, you may need to grant Full Disk Access to your launcher (Terminal/Xcode).
- Exclusions and toggles apply immediately; an in-progress scan may be canceled and restarted automatically.
