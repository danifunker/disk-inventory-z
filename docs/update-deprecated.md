# Plan: Resolve Deprecated APIs in Disk Inventory Z

## PROGRESS (updated for v1.6.0 release)
Stages 1–7 are landed and shipped in **v1.6.0**. A pile of fix-forward work
landed alongside Stages 5–7 when the modernization surfaced latent bugs; the
table below records that too so the next session has the full picture.

| Stage | Status | Key commits |
|---|---|---|
| 1 Dead code (NTID3Helper) | ✅ done | 464a17c |
| 2 Enum/constant renames | ✅ done | cda96ca |
| 3 Drawing/nib/geometry/progress | ✅ done | 6d0417c, b432619 (icon y-centering follow-up) |
| 4 Legacy CocoaTech internals | ✅ done | 931ffc4 |
| 5 UTType + pasteboard | ✅ done | aff87e9 |
| 6 NSWorkspace + document open | ✅ done | 38cf23a, 47a142a (+walker fix), 7a0d95b (bypass NSDocumentController) |
| 7 Alert / sheet modernization | ✅ done | dbe1978 |
| 7.5 Bug fixes uncovered by the modernization | ✅ done | 47a142a, 1085503, a41ed6e |
| 7.6 Stale-identifier cleanup | ✅ done | b9f4c4e, 01f69f4, f3442c4 |
| 7.7 UI polish before release | ✅ done | 94d1513, f258870 |
| 7.8 v1.6.0 release | ✅ tagged | 5126ad6 |
| 7.9 nib→xib conversion (MainMenu, TreeMap, LoadingPanel) | ✅ done | 0d25a91 + v1.7.0 |
| 8 NSDrawer → NSSplitView + selection-list panel | ✅ done | v1.7.0 |
| **8.5 Async filesystem scan + Wave 2 live UI** | ✅ done | v2.0.0 |
| **9 Hardening (warnings-as-errors)** | ✅ done | v2.0.0 |

### Deprecation warning count
**~100 → 0.** Stage 8 removed the last 36 (`NSDrawer`/`NSDrawer*`).
Build is clean against the macOS 26.5 SDK at deployment target 13.0.

### Stage 8 — what actually shipped (v1.7.0)
Rather than `NSSplitViewController`, the drawers were replaced with a nested
plain `NSSplitView` layout (lower-risk drop-in that kept `MainWindowController`
intact). Both `MainMenu.nib` and the document window's `TreeMap.nib` were
converted to editable `.xib` first (Stage 7.9); the structural reshape is
scripted in `scripts/stage8_reshape_treemap_xib.py` so all four locales stay
in sync. Layout: files-outline | file-kinds across the top (60/40), treemap
full-width on the bottom, paneSplitter dividers. The selection-list view moved
out of its bottom drawer into a floating `NSPanel`
(`SelectionListPanelController`, shown on demand). Plus a pile of UX work:
30-colour palette (was 12), `internaldrive`/SF-Symbol toolbar icons + a
"Choose Another Disk" item, quit-on-last-window-close, a fix for the
`TMVCushionRenderer` "_rect exceeds bitmap width" assert (fractional column
width → floor the bitmap size), and the initial-layout nudge that forces the
table scrollViews to tile so row 0 sits below the header.

### Why Stages 8 / 8.5 / 9 were deferred
- **Stage 8** needs Interface Builder. The two drawers (`_kindsDrawer`,
  `_selectionListDrawer`) live in the binary `MainMenu.nib`; converting to
  `NSSplitViewController` requires nib edits and visual confirmation of
  toggle / resize / width-persistence behaviour. Code touch points are
  listed in Stage 8 below.
- **Stage 8.5** is an architectural refactor (the directory scan currently
  runs synchronously on the main thread and pumps the runloop). The right
  time to do it is after the `NSDrawer` migration, but before turning on
  warnings-as-errors so any new background-thread work doesn't get
  compounded with deprecation tightening.
- **Stage 9** is the final lock-in — only worth doing when the warning
  count truly hits zero (which means Stage 8 is done).

### Bug fixes uncovered while doing the modernization
These were latent bugs in the existing codebase that the Stage 5–7 work made
visible (because `NSParameterAssert` started firing in Debug, or because the
new APIs route through different framework code paths).

- **`FSItem.m` scan-walker stack corruption** (47a142a). The periodic
  runloop-pump every 64 files re-invoked `-fsItemEnteringFolder:` with the
  current folder, which has push semantics and asserts
  `lastObject == [item parent]`. In Release the assert was compiled out but
  the stack still accumulated duplicates, silently skewing the progress-panel
  folder-name display. Latent since the 2019 Catalina-support commit. Fixed by
  adding a dedicated `-fsItemShouldContinueLoading` delegate method with no
  stack semantics for the pump.
- **`LoadingPanelController` double-release** (1085503). Stage 3 migrated to
  `-loadNibNamed:owner:topLevelObjects:` and added a retaining
  `nibTopLevelObjects` array. But the nib still had "release when closed" on
  the panel, so closing the panel post-scan freed it while
  `nibTopLevelObjects` still held a reference → `EXC_BAD_ACCESS` during a
  later runloop autorelease-pool pop. Fixed by `setReleasedWhenClosed:NO` on
  both `init` and `initAsSheetForWindow:` paths.
- **`NSDocumentController` URL-open coordination crash** (7a0d95b). The
  Stage 6 switch from `openDocumentWithContentsOfFile:display:` to the
  URL-based async API routed reads through `NSFileCoordinator`, whose
  continuation block fires on the main thread *while* our synchronous scan
  was still pumping the runloop. The block's autorelease pool would pop
  mid-scan and over-release. Worked around by overriding
  `openDocumentWithContentsOfURL:display:completionHandler:` to bypass
  `NSDocumentController` entirely and own the document lifecycle directly
  (`alloc/init` `FileSystemDoc`, set URL/type, call `-scanFolderAtURL:error:`,
  `addDocument:`/`makeWindowControllers`/`showWindows`). This is **the
  motivation for Stage 8.5** — see below; making the scan asynchronous will
  let us drop the bypass and play nice with the framework.
- **First-launch filter switches inconsistent** (a41ed6e). `DrivesPanelController`
  was registering its `DIXShow*` defaults *after* `-rebuildVolumesArray` had
  already consumed them on first build. Moved registration to `+initialize`.

### Other UI / polish work landed in v1.6.0
Not strictly deprecation work, but tracked here because it shared files
with the modernization and ended up in the same release:

- **Stale-identifier purge.** `NTID3Helper` (dead), `DIXLegacyOmniHelpers`
  (replaced 7 call sites with `[x length] == 0/!= 0`), `OB*` macros
  (`OBPRECONDITION` → `NSParameterAssert`, others were unused),
  `NSApplication(Omni)` category (restored shift-to-slow-zoom with modern
  `NSApp.currentEvent.modifierFlags`), `OmniAppKitExtensions` project group
  → `AppKitExtensions`, misleading `Preferences.strings` comments, the
  `DiskInventoryXBoolHelpers` category rename, stray `Re: DiskInventory X is
  not compatible…` comment text.
- **Column sizing.** New `DIXTableView+Sizing` category centralises rules for
  all four tables (outline / kinds drawer / selection list / drives panel):
  column min-widths ≥ header text, numeric columns clamped to "1234.5 GB"
  width, the named flex column absorbs extra width, **every** non-numeric
  text column tail-truncates with `…` via a `DIXTruncatingTextFieldCell`
  subclass that draws via `NSAttributedString -drawWithRect:options:` so
  truncation works even when bindings supply attributed strings. Custom
  cells (`ImageAndTextCell`) are excluded from the swap so the name+icon
  pairing on the outline view and selection list survives.
- **Dark-mode color fix.** `DIXTruncatingTextFieldCell` now injects
  `textColor` (defaults to `controlTextColor`, which is appearance-aware)
  into any character range of the attributed-string value that lacks a
  foreground colour. Fixes the drives panel's volume-name transformer,
  which doesn't set a colour, appearing in black on dark mode.
- **Window layout.** `constrainWindowToScreen` clamps the document window
  to `visibleFrame - 280pt below - 560pt right - 20pt margin`, with
  400pt/700pt safety floors. Called inline in `-awakeFromNib` and again
  deferred via `dispatch_async` to override frame-autosave restoration.
  Kinds drawer widened to 420pt at install time; both drawers pinned to
  `NSMaxXEdge`. The status-bar install also walks descendant
  `NSScrollView`s and re-tiles them (since `setFrame:` with same size only
  changes origin and `NSScrollView` doesn't auto-re-tile then). The main
  outline / file-kinds / selection-list headers got an opaque
  `DIXOpaqueTableHeaderView` to stop rows scrolling under them from
  visually bleeding through.
- **Right-click "Show Files in Selection List".** Notification-based wiring
  (`DIXShowKindInSelectionListNotification`) so the outline view's context
  menu and the file-kinds drawer's new context menu both route through
  `FileKindsTableController`'s existing
  `-showFilesInSelectionList:` action.
- **Drives panel: first disk auto-selected** on initial build; subsequent
  rebuilds preserve manual selection.
- **`NSDrawerOpaqueTableHeaderView`-related accumulation:** see `Stage 8`
  for the only remaining warning class.

---


## Goal
Eliminate all ~100 `-Wdeprecated-declarations` warnings emitted by a clean build
against the macOS 26.5 SDK (deployment target 13.0), without behavior regressions,
and leave the build configured so new deprecations cannot creep back in.

## Guiding principles (efficiency / no rework)
1. **Touch each line once.** Work is sequenced so a given call site is rewritten in
   exactly one stage. The notable trap is *constants embedded inside deprecated
   method calls* (e.g. `NSCompositeSourceOver` inside `compositeToPoint:operation:`):
   these are handled together with the method rewrite, **not** in the bulk
   constant-rename stage, so we don't edit the same line twice.
2. **Group co-located, interdependent changes.** The pasteboard-type and UTType
   migrations touch the same lines in `FSItem.m` and `NTFilePasteboardSource.m`, so
   they are a single stage. This keeps `FSItem.m` (the most delicate file) opened once.
3. **Cheapest / safest first, riskiest / most architectural last.** Dead-code removal
   and mechanical token swaps go early to shrink the warning count and de-noise later
   diffs; `NSDrawer` → `NSSplitViewController` goes last so every other change is
   already stable when we do the big restructure.
4. **One commit per stage.** Each stage below ends at a buildable, testable state.
   Commit message conventions: `deprecation(stage N): <summary>`.

## Tracking the warning count
Use this to measure progress at the start/end of each stage (expect it to fall
monotonically to 0):

```sh
xcodebuild -project "Disk Inventory Z.xcodeproj" -scheme "Disk Inventory Z" \
  -configuration Debug CODE_SIGNING_ALLOWED=NO clean build 2>&1 \
  | grep -cE "repos/disk-inventory-z.*warning:.*deprecated"
```

Baseline at plan creation: **~100 in-project deprecation warnings**.

## Inventory snapshot (what's actually live)
- `CocoaTech-Depreciated/` is **misleadingly named** — most of it is live code:
  - `NTFilePasteboardSource` is called from `FSItem.m:805` (drag/drop).
  - `NTInfoView` → `NTTitledInfoView` → `NTTitledInfoPair` is the superclass chain of
    `DIXFileInfoView`, used by `InfoPanelController`.
  - `NTID3Helper.{h,m}` is **dead**: not in the Xcode Sources phase, no references. ⇒ removable.
- Compiled sources are listed in the project's `Sources` build phase; `NTID3Helper.m`
  is **not** among them.

---

## Stage 1 — Baseline & dead-code removal
**Why first:** zero-risk reduction of clutter; establishes the measurement workflow.

Tasks:
1. Record the baseline warning count (command above) at the top of the PR/commit body.
2. Delete `CocoaTech-Depreciated/NTID3Helper.h` and `.m` from disk.
3. Remove their `PBXFileReference` / `PBXBuildFile` / group entries from
   `Disk Inventory Z.xcodeproj/project.pbxproj` (it is not in Sources, but the file
   reference may still exist in the navigator group).
4. `grep -rn "NTID3Helper\|ID3"` to confirm no remaining references.

Exit criteria: clean build succeeds; warning count unchanged (NTID3Helper wasn't
compiled) but file count reduced. **Commit.**

---

## Stage 2 — Mechanical constant / enum renames
**Why here:** pure token substitution, no behavior change, no API restructuring.
Knocks out the largest count of low-risk warnings and de-noises later diffs.
**Exclusion (anti-rework):** do **not** touch constants that live inside a deprecated
*method* call that a later stage rewrites — specifically `NSCompositeSourceOver` at
`ImageAndTextCell.m:199` (handled in Stage 3).

Renames (search-and-replace, verify each in context):

| Deprecated | Replacement | Sites |
|---|---|---|
| `NSCompositeCopy` | `NSCompositingOperationCopy` | `TreeMapView/TreeMapView.m:168,205`, `TMVItem.m:144`, `ZoomInfo.m:145` (all inside non-deprecated `drawInRect:…` / `NSFrameRectWithWidthUsingOperation`) |
| `NSRightTextAlignment` | `NSTextAlignmentRight` | `VolumeUsageTransformer.m:91,109`, `NTTitledInfoView.m:464` |
| `NSLeftTextAlignment` | `NSTextAlignmentLeft` | `NTTitledInfoView.m:486` |
| `NSRightMouseDown` | `NSEventTypeRightMouseDown` | `TreeMapViewController.m:199` |
| `NSShiftKeyMask` | `NSEventModifierFlagShift` | `ZoomInfo.m:42` |
| `NSSmallControlSize` | `NSControlSizeSmall` | `NTInfoView.m:121,123` |
| `NSOnState` | `NSControlStateValueOn` | `FileSystemDoc.m:1184` |
| `NSNoSelectionMarker` | `NSBindingSelectionMarker.noSelectionMarker` * | `GenericArrayController.m:212`, `SelectionListTableController.m:202,240`, `FileKindsTableController.m:216` |
| `NSNotApplicableMarker` | `NSBindingSelectionMarker.notApplicableMarker` * | `GenericArrayController.m:136,143` |
| `NSMultipleValuesMarker` | `NSBindingSelectionMarker.multipleValuesMarker` * | `GenericArrayController.m:222` |

\* The KVB markers became class properties on `NSBindingSelectionMarker` (macOS 11).
In ObjC: `NSBindingSelectionMarker.noSelectionMarker` etc. Verify the comparison
sites still compare against the same singleton objects.

Exit criteria: clean build; warning count drops by the count above; no behavior change.
**Commit.**

---

## Stage 3 — Drawing, nib-loading, window geometry, progress indicator
**Why here:** small, localized code changes (not just renames) that don't depend on
the bigger migrations. Includes the deprecated-method rewrites whose embedded
constants were deferred from Stage 2.

Tasks:
1. **`compositeToPoint:operation:`** → `drawAtPoint:fromRect:operation:fraction:`
   (or `drawInRect:…`). `ImageAndTextCell.m:199`. Replace `NSCompositeSourceOver`
   inline with `NSCompositingOperationSourceOver` as part of this rewrite.
2. **`colorSpaceName` / `colorUsingColorSpaceName:`** → `colorUsingColorSpace:`
   (e.g. `NSColorSpace.genericRGBColorSpace` / `.deviceRGBColorSpace` matching the old
   name) or `colorUsingType:`. `TMVCushionRenderer.m:100,101,461,462`. **Verify the
   cushion-shading colors render identically** — color-space choice affects output.
3. **`convertBaseToScreen:`** → `convertPointToScreen:` (note: takes/returns a point,
   not a rect; adjust call). `MainWindowController.m:91`.
4. **`loadNibNamed:owner:`** → `loadNibNamed:owner:topLevelObjects:`.
   `LoadingPanelController.m:43,88`, `InfoPanelController.m:36`, `DrivesPanelController.m:97`.
   Must retain a strong reference to the returned top-level objects (the old API leaked
   them intentionally; the new one requires the caller to own them). Confirm windows/views
   are not deallocated prematurely.
5. **`NSProgressIndicatorBarStyle` / `NSProgressIndicatorPreferredLargeThickness`**
   → drop the deprecated style/thickness constants; use `controlSize` + `sizeToFit`.
   `DrivesPanelController.m:454,517`.

Exit criteria: clean build; manual smoke test of the affected UI (file-info cell
icons, treemap cushion colors, loading panel, drives panel progress bars, window
positioning). **Commit.**

---

## Stage 4 — Legacy CocoaTech internals (Carbon + flush-window + clip view)
**Why here:** self-contained within `CocoaTech-Depreciated/`, independent of the
pasteboard/alert/drawer work. Grouping them keeps those two files opened once.

Tasks:
1. **Carbon File Manager** `FSPathMakeRef` + `FSGetCatalogInfo` (`NTInfoView.m:433,437`).
   Replace with `NSURL` resource values (`URLResourceKey` such as
   `NSURLFileSecurityKey` / POSIX permissions via `NSFileManager attributesOfItemAtPath:`
   `NSFilePosixPermissions`). Confirm the permissions string shown in the info view is
   identical for representative files.
2. **`setCopiesOnScroll:`** (`NTInfoView.m:117`) — now a no-op; remove the call.
3. **`disableFlushWindow` / `enableFlushWindow` / `isFlushWindowDisabled`**
   (`NTTitledInfoView.m:125,128,135,149,152,163`). Remove the flush gating; if the
   batching mattered, wrap the updates in
   `+[NSAnimationContext runAnimationGroup:completionHandler:]`. In practice these can
   usually just be deleted on a layer-backed/auto-flushing AppKit.

Exit criteria: clean build; info panel still shows correct name/size/permissions and
repaints without flicker. **Commit.**

---

## Stage 5 — UTType + pasteboard unified migration
**Why grouped:** these are the *same lines* in `FSItem.m` and `NTFilePasteboardSource.m`;
splitting UTType vs. pasteboard-type would force editing those files twice.
**This is the most behavior-sensitive stage** (drag/drop, copy, type detection).

Tasks:
1. Add `#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>` and link the
   `UniformTypeIdentifiers.framework` in the project.
2. Replace the `kUTType*` C constants and functions with the `UTType` class:
   - `UTTypeCopyDescription((CFStringRef)uti)` → `[UTType typeWithIdentifier:uti].localizedDescription`
     (`FSItem.m:608`).
   - `UTTypeConformsTo(a, kUTTypeImage)` → `[utTypeA conformsToType:UTTypeImage]`
     (`FSItem.m:770,784`).
   - `kUTTypeRTF/RTFD/HTML/PDF/Image/FlatRTFD` → `UTTypeRTF`/`UTTypeRTFD`/`UTTypeHTML`/
     `UTTypePDF`/`UTTypeImage`/`UTTypeFlatRTFD` (`FSItem.m:762–786`,
     `NTFilePasteboardSource.m:110–116,161`).
   - Where code currently compares UTI **strings**, switch to comparing `UTType`
     objects (`isEqual:` / `conformsToType:`); centralize the string→`UTType` conversion.
3. Replace deprecated pasteboard type constants:
   - `NSStringPboardType`→`NSPasteboardTypeString`, `NSTIFFPboardType`→`NSPasteboardTypeTIFF`,
     `NSRTFPboardType`→`NSPasteboardTypeRTF`, `NSRTFDPboardType`→`NSPasteboardTypeRTFD`,
     `NSHTMLPboardType`→`NSPasteboardTypeHTML`, `NSPDFPboardType`→`NSPasteboardTypePDF`,
     `NSPostScriptPboardType`→`@"com.adobe.encapsulated-postscript"`.
     (`FSItem.m:753–788`, `NTFilePasteboardSource.m:39–116`).
   - **`NSFilenamesPboardType` is the delicate one** (`FSItem.m:753,781`,
     `MainWindowController.m:45`, `NTFilePasteboardSource.m:49,102`). It used a single
     property-list-of-paths item. The modern model is one `NSPasteboardItem` per file
     using `NSPasteboardTypeFileURL`. Rework `writeToPasteboard:` /
     `NTFilePasteboardSource file:toPasteboard:types:` to write file-URL items, and
     update the `registerForDraggedTypes:` / `validRequestorForSendType:` /
     reading side in `MainWindowController.m:45` accordingly.
4. Re-test thoroughly: drag a file to Finder/another app, ⌘C then paste into TextEdit
   (RTF/HTML/PDF/image variants), and the services send-types path.

Exit criteria: clean build; drag/drop and copy/paste verified across the type
variants above; kind-name column still populated. **Commit.**

---

## Stage 6 — NSWorkspace & document-open APIs
**Why here:** independent of the above; introduces async completion handlers, so
isolate it for focused testing.

Tasks:
1. **`openFile:withApplication:`** (`AppsForItem.m:118`) →
   `openApplicationAtURL:configuration:completionHandler:` /
   `openURLs:withApplicationAtURL:configuration:completionHandler:`.
2. **`LSCopyApplicationURLsForURL`** (`AppsForItem.m:151`, LaunchServices C API; not
   flagged by the compiler but deprecated since macOS 12) →
   `[NSWorkspace.sharedWorkspace URLsForApplicationsToOpenURL:]`. Do this together with
   #1 since both live in `AppsForItem.m` and feed the "Open With" menu.
3. **`openDocumentWithContentsOfFile:display:`** (+ `shouldCreateUI`)
   (`MyDocumentController.m:79,114`) →
   `openDocumentWithContentsOfURL:display:completionHandler:`. Adapt the two call sites
   to the async completion-handler shape; ensure callers that relied on the synchronous
   return value are restructured.

Exit criteria: clean build; "Open With <app>" works; opening a volume/folder document
works from both call paths. **Commit.**

---

## Stage 7 — Alert / sheet modernization
**Why late, before drawers:** changes control flow (synchronous `didEndSelector`
callbacks → async completion blocks); want it stable before the drawer restructure
touches the same controllers.

Tasks (replace all with `NSAlert` + `beginSheetModalForWindow:completionHandler:`):
1. **`NSBeginInformationalAlertSheet`** — `MainWindowController.m:422,436,725`,
   `FileSystemDoc.m:575,622`.
2. **`NSBeginAlertSheet`** — `MainWindowController.m:322`.
3. Return-code constants: **`NSAlertAlternateReturn`** (`MainWindowController.m:336,687`)
   → map to `NSAlertFirstButtonReturn` / `NSAlertSecondButtonReturn` per button order;
   **`NSRunContinuesResponse`** (`LoadingPanelController.m:234`) → `NSModalResponseContinue`.
4. **`beginSheet:modalForWindow:modalDelegate:didEndSelector:contextInfo:`**
   (`LoadingPanelController.m:91`) → `[NSWindow beginSheet:completionHandler:]`.
5. Fold each old `didEnd:returnCode:contextInfo:` delegate body into the completion
   block; verify button-index semantics (NSAlert button order is reversed vs. the old
   default/alternate/other ordering).

Exit criteria: clean build; trigger each alert (delete confirmation, error sheets,
loading-cancel) and confirm correct button wiring. **Commit.**

---

## Stage 8 — `NSDrawer` → `NSSplitViewController`
**Why last:** largest, most architectural change; touches XIBs and several controllers.
Doing it last means every other warning is already gone and the diff is isolated.

Tasks:
1. Identify the drawer(s) in the main window nib and what they host (the selection list
   / file-kinds side panels).
2. Replace `NSDrawer` with an `NSSplitViewController` (or an embedded split view with a
   collapsible sidebar via `NSSplitViewItem.collapsed`). Update:
   - `MainWindowController.h:11,12,26,27` and `MainWindowController.m:195,200`
     (drawer outlets/open-close logic → split-view item show/hide).
   - `SelectionListTableController.m:42,46,50,58` — replace `NSDrawer*` types,
     `NSDrawerWillOpenNotification` / `NSDrawerDidCloseNotification` /
     `NSDrawerClosedState` with split-view-item KVO on `isCollapsed` (or explicit
     show/hide hooks).
   - `FileKindsTableController.m:92` — `NSDrawerClosingState` / `NSDrawerClosedState`
     state checks → `isCollapsed`.
3. Update the toolbar/menu items that toggle the drawer to toggle the sidebar instead.
4. Migrate the relevant XIB/nib so the panel is a split-view item; preserve sizes and
   the user-defaults-persisted width.
5. Heavy manual test: open/close the side panel, resize, persistence across launches,
   selection-list and file-kinds interactions.

Exit criteria: clean build; side-panel behavior matches the old drawer (toggle,
animate/collapse, width persistence). **Commit.**

---

## Stage 8.5 — Asynchronous filesystem scan (NEW)
**Why this stage exists.** During Stage 6, switching from the deprecated
`openDocumentWithContentsOfFile:display:` to
`openDocumentWithContentsOfURL:display:completionHandler:` exposed an
architectural mismatch: the URL-based open API routes through
`NSFileCoordinator`, which dispatches a continuation block back to the main
thread *while the read is in progress*. Our scan runs **synchronously on the
main thread** and pumps the runloop via `_progressController runEventLoop`,
so the coordinator's continuation block fires mid-scan, its per-callout
autorelease pool pops, and an over-release crashes with `EXC_BAD_ACCESS` in
`__RELEASE_OBJECTS_IN_THE_ARRAY__`. The v1.6.0 release works around this by
overriding `openDocumentWithContentsOfURL:` to bypass `NSDocumentController`'s
URL-based open entirely (see 7a0d95b). That works, but it's a band-aid: the
underlying problem is that the scan blocks the main thread.

Making the scan asynchronous fixes the root cause, removes the bypass, and
unlocks a number of secondary improvements. **Do this before Stage 9** so the
hardening pass locks in the post-refactor state.

### What needs to change

1. **`FSItem.loadChildren` / `loadChildrenAndSetKindStrings:usePhysicalSize:`**
   The directory walker (currently in `FSItem.m` around lines 936–1220) runs
   `NSDirectoryEnumerator` + `FSItem` allocations + delegate calls on the
   calling thread. Move the entire walk onto a background `dispatch_queue_t`
   (or `NSOperationQueue` if cancellation needs to be more structured) and
   keep `FSItem`'s internal `_childs`, hardlink-dedup set, and per-item
   resource caches local to that queue until the walk finishes.

2. **Progress / cancel signalling**
   `fsItemEnteringFolder:`, `fsItemExittingFolder:`, and (added in 47a142a)
   `fsItemShouldContinueLoading` are the only points where the walker talks
   to the UI. Route them to the main thread via `dispatch_async` with
   batched updates (e.g. coalesce progress text updates so we don't post
   10k notifications per second on large scans). `cancelPressed` is read on
   the walker thread → make it atomic (`_Atomic BOOL` or
   `OSAtomicCompareAndSwap`) so a main-thread Cancel click is visible
   without locks.

3. **Completion handling on the main thread**
   When the walker finishes (success or cancel), hop back to main and:
   - Set `_rootItem` on `FileSystemDoc`.
   - Call `refreshFileKindStatistics`.
   - Close the progress panel.
   - Invoke the completion block originally passed into
     `openDocumentWithContentsOfURL:display:completionHandler:`.

4. **Remove the `NSDocumentController` bypass**
   Once the scan is non-blocking, the `NSFileCoordinator` continuation no
   longer interleaves with our work. Delete the override of
   `openDocumentWithContentsOfURL:display:completionHandler:` in
   `MyDocumentController.m`, restore `readFromURL:ofType:error:` as a proper
   `NSDocument` override on `FileSystemDoc`, and let the framework handle
   document lifecycle (addDocument, makeWindowControllers, showWindows).

5. **Cancel + close interaction**
   Today closing the document during a scan is impossible because the main
   thread is blocked. After async, the user could close the window mid-scan:
   the document's `dealloc` (or `close` override) must cancel the walker
   and wait for it to acknowledge before tearing down `_rootItem`. The
   `cancelPressed` flag + a completion-on-cancel callback are sufficient.

6. **Drives panel mount/unmount during scan**
   `DrivesPanelController` observes `NSWorkspace` mount notifications and
   triggers `rebuildVolumesArray`. Today these can't race with a scan
   (main-thread blocked). After async, ensure the volumes table updates
   freely while a scan runs — should already work since the rebuild is
   main-thread.

### Why now is the right time
- The Stage-8 work (NSDrawer → NSSplitViewController) doesn't touch the
  scan at all, so it can land independently of this.
- Doing this *after* Stage 8 means the NSDrawer migration is done with
  the existing synchronous scan as a known constant; one architectural
  axis at a time.
- Doing this *before* Stage 9 (warnings-as-errors) means any new
  deprecation introduced by switching to `NSOperationQueue` / dispatch /
  whatever modern async primitive is chosen will surface during the
  refactor, not as a CI failure after lock-in.

### Test surface this stage needs
- Cancel a long scan via the panel's Cancel button → walker terminates,
  progress panel closes, no leaked window/document.
- Close the document mid-scan → walker terminates, no over-release on
  `_rootItem` access from the still-running walker.
- Quit the app mid-scan → `applicationShouldTerminate:` must wait for or
  cancel in-flight walkers.
- Volume mount / unmount during scan → drives panel updates without
  affecting the scan.
- Open multiple documents concurrently → each runs its own walker; no
  shared mutable state collisions (`g_seenHardlinkInodes` is currently
  a global — needs to become per-walk).

### Exit criteria
- Document open uses the framework's `NSDocumentController` URL-based open
  again (the v1.6.0 bypass is deleted).
- Scans run off the main thread; UI stays responsive through long walks
  (no beach-ball, menu items work, About panel opens during a scan).
- Cancel + close + quit interactions all clean up the walker correctly.
- No deprecation regressions introduced. **Commit.**

### Stage 8.5 — what actually shipped (v2.0.0)
- **Async engine.** Per-doc serial `_scanQueue`; walker runs off main; atomic
  cancel flag; ~4 Hz dispatch_sync refresh barrier from worker → main updates
  the inline overlay (path + count + elapsed clock).
- **Top-level orchestration.** `runTopLevelOrchestrationForURL:` enumerates the
  scan root's direct children itself, builds each as a detached orphan FSItem
  on the worker, then dispatches each completed orphan to main where it splices
  into `_rootItem` via `insertChild:updateParent:YES`. `_rootItem` is only
  mutated on main, so AppKit redraws never race the worker.
- **Live UI.** Outline view + file-kinds table populate as top-level subtrees
  complete; treemap waits for scan-finish and rebuilds once (with kindColors
  reset first, so the palette is assigned in size-descending order).
- **Inline overlay.** Replaces the loading sheet entirely — centered floating
  panel over the doc window with spinner, path, item count, elapsed clock,
  Cancel button. Doc window stays fully responsive (no sheet-modal).
- **Cancel.** Swaps the partial `_rootItem` for an empty stub before closing
  so AppKit's deferred CA-flush during termination has nothing freed to walk.
  Closes the doc, which re-shows the drives panel (so the user lands back on
  the disk-selection screen instead of quitting).
- **Tahoe magic-dir skips.** `/.nofollow` and `/.resolve` (macOS 26
  symlink-resolution re-rooted views) skipped at both top-level and deep-walk
  levels so disk-usage totals are correct.
- **Concurrency.** Hardlink dedup `g_seenHardlinkInodes` now guarded by
  `os_unfair_lock` so multiple open docs scanning in parallel don't corrupt
  the shared set.
- **Bug fixes uncovered along the way.** `FSItem.insertChild:updateParent:`
  no longer calls the long-gone Omni category `-insertObject:inArraySortedUsingSelector:`
  (used `NSBinarySearchingInsertionIndex` instead) — also unblocks
  `moveItemToTrash:` / `refreshItem:` which would have hit the same crash.
- **Drives panel polish.** Re-fits to natural size on each `showPanel` (was
  inheriting doc-window size); resizes to fit row count when toggles flip;
  defaults for Network / External / Mounted Images switched to OFF on first
  launch (local-drives-only default).
- **Ancillary panels.** Selection list + disk-usage pie are ordered out when
  the main doc window closes. Info panel reposition logic to avoid covering
  the doc window's cancel overlay (drops below pie panel when present).

---

## Stage 9 — Hardening & guard against regressions
**Why:** lock in the result so new deprecations fail the build.

**Prerequisites:** Stages 8 and 8.5 must be complete first. Stage 8 takes the
last 36 warnings (`NSDrawer*`) to zero; Stage 8.5 reverts the
`NSDocumentController` bypass so the document-open path uses non-deprecated
framework APIs end-to-end. Doing this stage before either of those would
either fail the zero-warning check or lock in a workaround we intend to
remove.

Tasks:
1. Confirm the warning count command reports **0**.
2. Enable `CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES` and add
   `-Werror=deprecated-declarations` (or `GCC_TREAT_WARNINGS_AS_ERRORS` scoped to this
   warning) to the Release configuration so future deprecations break CI.
3. Full regression pass: scan a volume, treemap render, file selection, info panel,
   drag/drop, copy/paste, open-with, all alerts, side panel, preferences. Add
   cancel-mid-scan and close-mid-scan to the regression set now that the scan
   is asynchronous (Stage 8.5).
4. Update `README` / changelog noting the minimum-OS-relevant API modernization.

Exit criteria: 0 deprecation warnings; warnings-as-errors active; full app smoke test
green. **Commit.**

---

## Stage → file touch map (verify no file is reworked on the same lines)
| File | Stages that touch it | Overlap risk |
|---|---|---|
| `FSItem.m` | 5 (done), **8.5 (walker thread)** | different concerns ✓ |
| `NTFilePasteboardSource.m` | 5 | single ✓ |
| `MainWindowController.{h,m}` | 3 (geom), 7 (alerts), 8 (drawer) | different lines ✓ |
| `FileSystemDoc.m` | 2 (`NSOnState`), 7 (alerts), 6 (URL scan rename, done), **8.5 (async hop + lifecycle)** | different lines ✓ |
| `LoadingPanelController.m` | 3 (nib), 7 (sheet/return code), **8.5 (atomic cancel)** | different lines ✓ |
| `MyDocumentController.m` | 6 (done), **8.5 (delete URL-open bypass)** | the bypass added in 7a0d95b is deliberately removed in 8.5 |
| `SelectionListTableController.m` | 2 (markers), 8 (drawer) | different lines ✓ |
| `FileKindsTableController.m` | 2 (markers), 8 (drawer) | different lines ✓ |
| `GenericArrayController.m` | 2 (markers) | single ✓ |
| `NTInfoView.m` | 2 (control size), 4 (Carbon/clip) | different lines ✓ |
| `NTTitledInfoView.m` | 2 (text align), 4 (flush window) | different lines ✓ |
| `TreeMapView/*`, `ImageAndTextCell.m` | 2/3 (composite, color) | composite-in-method deferred to 3 ✓ |
| `AppsForItem.m` | 6 | single ✓ |

The only files entered in more than one stage are touched on disjoint lines by design;
the composite/marker constants embedded in deprecated method calls are deliberately
deferred to the stage that rewrites the surrounding call so no line is edited twice.
Stage 8.5 explicitly *deletes* lines added in commit 7a0d95b (the
`NSDocumentController` URL-open bypass) — that's the only intentional
re-touch in the plan and is documented in Stage 8.5's "Remove the
`NSDocumentController` bypass" step.
