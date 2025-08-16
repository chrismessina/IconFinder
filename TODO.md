# TODO.md

High-level plan to modernize IconFinder (Objective-C AppKit) and then migrate to Swift/SwiftUI. Tasks are grouped by phase and ordered for efficient execution. We’ll update scope after your answers to the questions at the top.

## Open Questions (please answer to finalize scope)

1. Signing and team info: Do you have a Developer ID Application signing identity and Team ID we can use locally for signing/notarization? Any constraints on bundle identifier changes?

Yes, I have an account. I don't want to change the bundle identifier as I would like to contribute my changes back to the open source project found here: https://github.com/jrhodes/IconFinder

2. Minimum macOS support: Is macOS 13.5 the minimum you want, or can we require newer (e.g., 14+) for API access and SwiftUI features? Do you still need Intel support (Universal) or Apple Silicon only is acceptable?

Apple Silicon is fine. macOS 14+ is ok.

3. Scanning strategy: Is it acceptable to add a Spotlight mode (fast) using `mdfind` and keep a “deep scan” (slow, full filesystem) as an option? Which should be default?

Yes, two scanning modes is acceptable. The default should be fast. A toggle should be added for a "Deep scan".

4. Dependencies: Are third-party dependencies via Swift Package Manager allowed (for thumbnails, diffing, etc.), or do you prefer zero external deps?

Third-party dependencies via Swift Package Manager are acceptable.

5. Distribution: Do you want a repeatable local script for codesign + notarization only, or also CI-assisted (GitHub Actions) with secrets (Keychain / Apple ID / API key)?

Let's use GitHub Actions. I don't know how to use these or set them up, however.

6. UI/UX priorities: Any specific visual direction (sidebar, list/grid toggle, dark mode tweaks, quick preview), and do you want live filtering as you type?

UI priorities:

- modernize look and feel to use contemporary mac UI conventions
- improve UI performance of grid view
- add Dark Mode support
- Add live filtering to view
- generate metadata (e.g. keywords) for each asset based on the source, directory location where it was found, asset name, and anything else to improve live filtering
- Add spacebar to quick preview icons at largest available size
- Add ability to copy icon resource and to set copy format in preferences (e.g. icns, png, pdf)

7. Data storage: Is a simple plist fine, or should we move to a small database (SQLite/Core Data) for better scale and incremental updates?

Given the number of items typically found (10s of 1000s) we should use SQLite/Core Data.

---

## Phase 1 — Modernize Objective-C AppKit implementation (no UI rewrite)

- [ ] Replace deprecated sheet APIs: use modern sheet presentation (block-based) instead of `beginSheetModalForWindow:modalDelegate:didEndSelector:`.
- [ ] Safer, faster scanning engine:
  - [ ] Build an argument array for `/usr/bin/find` (no string-splitting) to avoid shell metacharacter issues.
  - [ ] Offer two modes: “Spotlight (fast)” via `mdfind` and “Deep Scan (full)” via `find`.
  - [ ] Add directory allow/deny lists (skip hidden/system/virtual volumes unless requested).
  - [ ] Throttle UI updates and batch-append results to reduce main-thread contention.
- [ ] Thumbnails and performance:
  - [ ] Use QuickLookThumbnailing to render thumbnails instead of loading full images.
  - [ ] Cache thumbnails to `~/Library/Caches/net.joerhodes.IconFinder/` with size keys.
- [ ] Data persistence improvements:
  - [ ] Switch to a compact on-disk format (binary plist or lightweight DB) with incremental save.
  - [ ] Store file metadata (uti, size, modDate) to support richer filters without re-touching disk.
- [ ] Concurrency and responsiveness:
  - [ ] Use GCD to process batches off the main thread; keep main thread for UI only.
  - [ ] Make Cancel immediate; terminate workers and close file handles safely.
- [ ] UI tweaks within AppKit:
  - [ ] Modern NSCollectionView flow layout; better selection/hover states; context menu (Reveal in Finder, Copy Path, Open With).
  - [ ] Live filter bar (extension/type, size ranges, updated-after) and text search across filenames.
- [ ] Logging, metrics, and privacy:
  - [ ] Replace print/NSLog with `os_log` and categories (scan, ui, performance).
  - [ ] Add a minimal “What gets scanned” note; no file contents read, only metadata and paths.
- [ ] Build settings & hardening:
  - [ ] Enable Hardened Runtime (non-sandboxed) for Developer ID builds.
  - [ ] Verify `MACOSX_DEPLOYMENT_TARGET`, architectures (arm64 + x86_64 if needed), and strip symbols in Release.
  - [ ] Turn on additional Clang warnings and static analyzer checks.
- [ ] Signing & Notarization (local script):
  - [ ] Add a script to archive, codesign with Developer ID, notarize via `notarytool`, and staple the ticket.
  - [ ] Parameterize Team ID, identity, and Apple API key credentials via environment variables.
- [ ] Documentation:
  - [ ] Update WARP.md with build/sign/notarize commands, Spotlight vs Deep Scan notes, and cache/thumbnails paths.

## Phase 2 — Swift + SwiftUI migration (parallelizable once Phase 1 scan core is stable)

- [ ] Introduce a Swift package/module for the scanning core:
  - [ ] Swift types for PathItem (id, url, ext, uti, size, modDate, thumbnail key).
  - [ ] AsyncSequence or Combine publisher that streams path discoveries in batches.
- [ ] SwiftUI app target (macOS app lifecycle):
  - [ ] App structure with menu commands (Scan, Stop, Clear Cache, Preferences...).
  - [ ] Views: Sidebar (filters), main grid (LazyVGrid) with thumbnails, detail popover/Quick Look.
  - [ ] Dark mode and dynamic type friendly.
- [ ] Integrations:
  - [ ] Use QLThumbnailGenerator from Swift; image cache with NSCache + disk cache.
  - [ ] Bridge to AppKit for “Open With…”, “Reveal in Finder”, and services.
- [ ] Feature parity checklist against Phase 1:
  - [ ] Scan modes, cancelation, progress, counts, filters, search, actions.
- [ ] Remove legacy ObjC UI layer after parity; keep ObjC wrappers only if needed for system APIs.
- [ ] CI (optional):
  - [ ] Build release, sign, and notarize; publish an artifact.
- [ ] Documentation:
  - [ ] Update WARP.md with SwiftUI commands and migration notes.

## Stretch goals (optional)
- [ ] Smart deduplication (same icon across bundles) and grouping by bundle/app.
- [ ] Export selection as a zip, preserving paths.
- [ ] Custom quick preview with zoom and metadata panel.

