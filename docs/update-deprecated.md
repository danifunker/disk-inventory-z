# Plan: Resolve Deprecated APIs in Disk Inventory Z

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

## Stage 9 — Hardening & guard against regressions
**Why:** lock in the result so new deprecations fail the build.

Tasks:
1. Confirm the warning count command reports **0**.
2. Enable `CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES` and add
   `-Werror=deprecated-declarations` (or `GCC_TREAT_WARNINGS_AS_ERRORS` scoped to this
   warning) to the Release configuration so future deprecations break CI.
3. Full regression pass: scan a volume, treemap render, file selection, info panel,
   drag/drop, copy/paste, open-with, all alerts, side panel, preferences.
4. Update `README` / changelog noting the minimum-OS-relevant API modernization.

Exit criteria: 0 deprecation warnings; warnings-as-errors active; full app smoke test
green. **Commit.**

---

## Stage → file touch map (verify no file is reworked on the same lines)
| File | Stages that touch it | Overlap risk |
|---|---|---|
| `FSItem.m` | 5 | single stage ✓ |
| `NTFilePasteboardSource.m` | 5 | single ✓ |
| `MainWindowController.{h,m}` | 3 (geom), 7 (alerts), 8 (drawer) | different lines ✓ |
| `FileSystemDoc.m` | 2 (`NSOnState`), 7 (alerts) | different lines ✓ |
| `LoadingPanelController.m` | 3 (nib), 7 (sheet/return code) | different lines ✓ |
| `SelectionListTableController.m` | 2 (markers), 8 (drawer) | different lines ✓ |
| `FileKindsTableController.m` | 2 (markers), 8 (drawer) | different lines ✓ |
| `GenericArrayController.m` | 2 (markers) | single ✓ |
| `NTInfoView.m` | 2 (control size), 4 (Carbon/clip) | different lines ✓ |
| `NTTitledInfoView.m` | 2 (text align), 4 (flush window) | different lines ✓ |
| `TreeMapView/*`, `ImageAndTextCell.m` | 2/3 (composite, color) | composite-in-method deferred to 3 ✓ |
| `AppsForItem.m`, `MyDocumentController.m` | 6 | single ✓ |

The only files entered in more than one stage are touched on disjoint lines by design;
the composite/marker constants embedded in deprecated method calls are deliberately
deferred to the stage that rewrites the surrounding call so no line is edited twice.
