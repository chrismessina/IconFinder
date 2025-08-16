# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Common developer commands

Environment variables used by the commands below:

- PROJ="IconFinder.xcodeproj"
- SCHEME="IconFinder"
- DERIVED=".build"  # repo-local DerivedData

List schemes and targets
- xcodebuild -list -project "$PROJ"

Build (Debug)
- xcodebuild -project "$PROJ" -scheme "$SCHEME" -configuration Debug -derivedDataPath "$DERIVED" -quiet build

Build (Release)
- xcodebuild -project "$PROJ" -scheme "$SCHEME" -configuration Release -derivedDataPath "$DERIVED" -quiet build

Run the built app (after a Debug build)
- APP_NAME="$(xcodebuild -project "$PROJ" -scheme "$SCHEME" -configuration Debug -showBuildSettings | awk -F= '/FULL_PRODUCT_NAME/ {gsub(/[[:space:]]/," ");print $2}' | tail -1)"; open "$DERIVED/Build/Products/Debug/$APP_NAME"

Clean
- xcodebuild -project "$PROJ" -scheme "$SCHEME" -configuration Debug -derivedDataPath "$DERIVED" -quiet clean
- rm -rf "$DERIVED"

Static analysis (Clang analyzer)
- xcodebuild -project "$PROJ" -scheme "$SCHEME" -configuration Debug -derivedDataPath "$DERIVED" -quiet clean analyze

Archive (Release)
- xcodebuild -project "$PROJ" -scheme "$SCHEME" -configuration Release -archivePath "$DERIVED/IconFinder.xcarchive" -quiet archive

Tests
- There are no test targets in this repository; single-test or test-suite commands do not apply.

## High-level architecture overview

- App lifecycle and controller
  - JRAppDelegate is the primary coordinator. On launch it loads previously cached image paths from ~/Library/Application Support/IconFinder/imagePaths.plist or kicks off a fresh scan.
  - Maintains imagePaths (all discovered images), filters (selected via NSSegmentedControl), and exposes filteredImagePaths via an NSPredicate. KVO is used so UI updates when filters or results change.

- Image discovery pipeline
  - Uses NSTask to invoke /usr/bin/find across the filesystem to locate common image types (jpeg, jpg, gif, png, icns, tiff, pdf).
  - Streams stdout through an NSPipe and subscribes to NSFileHandleReadCompletionNotification to append discovered paths incrementally.
  - Writes the final list to ~/Library/Application Support/IconFinder/imagePaths.plist for fast reloads on subsequent launches.
  - A Stop action terminates the running NSTask cleanly; a Remove Image Cache action deletes the plist and triggers a rescan.

- UI composition
  - MainMenu.xib defines the main window and connects outlets/actions on JRAppDelegate, including the segmented control used for filtering by file extension.
  - The grid is an NSCollectionView subclass (JRCollectionView). It handles double-click (mouseDown with clickCount == 2) to open the selected file via NSWorkspace.
  - JRImageCollectionItemView draws a subtle selection/border treatment. JRImageCollectionViewItemViewController is the item controller for per-cell presentation. An item XIB (JRImageCollectionViewItemViewController.xib) defines the cell UI.

- Data flow
  - find output → imagePaths (mutable backing store) → filteredImagePaths (predicate-applied) → collection view items → double-click opens file in the default app.

- Notable project settings (from project.pbxproj)
  - MACOSX_DEPLOYMENT_TARGET: 13.5
  - MARKETING_VERSION: 2.0
  - CURRENT_PROJECT_VERSION: 100
  - CLANG_USE_OPTIMIZATION_PROFILE: YES (OptimizationProfiles/ exists to support PGO)

## Usage notes

- Full Disk Access on modern macOS
  - Scanning the root volume (/) may be restricted. When debugging from the CLI or Xcode, grant Full Disk Access to the launching app (e.g., Terminal or Xcode) to ensure the NSTask-based search can read all directories.

- Long-running search and cancellation
  - The UI’s Stop control cancels the active NSTask. After stopping, filters and counts update and you can trigger a new scan.

- Cache location and reset
  - Cache file: ~/Library/Application Support/IconFinder/imagePaths.plist
  - Reset from the app’s UI (Remove Image Cache). From the CLI during development: rm -f "$HOME/Library/Application Support/IconFinder/imagePaths.plist"; next launch or the UI action will repopulate it.

