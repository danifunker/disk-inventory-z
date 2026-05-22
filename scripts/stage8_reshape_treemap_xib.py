#!/usr/bin/env python3
"""
Stage 8 reshape (v2): transform a TreeMap.xib so that:

  - NSDrawer objects (FileKindsDrawer id=21, SelectionListDrawer id=137)
    are removed.
  - The OASplitView (id=95) — which currently splits files-outline and
    treemap side by side — is replaced by a new nested split structure:

      contentView (id=23)
        ├── textField id=33  (file name label, unchanged)
        ├── textField id=45  (file size label, unchanged)
        └── splitView ST8-out  (vertical=NO → top/bottom)
            ├── splitView ST8-top  (vertical=YES → L/R)
            │   ├── scrollView id=63  (files outline, extracted)
            │   └── customView id=24  (kinds table, moved from top level)
            └── customView id=30      (treemap, extracted)

    Initial sizes: outer 40% top / 60% bottom; inner 35% files / 65% kinds.
    Divider style: thin (2 pt).

  - customView id=138 (selection list) stays as a TOP-LEVEL object in the
    xib — to be hosted in a floating NSPanel at runtime via the
    _selectionListPaneView outlet.

  - File's Owner connections:
      removed:  _kindsDrawer, _selectionListDrawer
      repointed: _splitter → ST8-out (the new outer split — this is the
                 split whose orientation the "Split Vertically/Horizontally"
                 menu item flips)
      added:    _kindsTopSplit (→ ST8-top, the top-half split)
                _kindsPaneView (→ id=24, kinds-table view)
                _selectionListPaneView (→ id=138, selection-list view)

Run as: python3 scripts/stage8_reshape_treemap_xib.py path/to/TreeMap.xib
"""
import re
import sys
import pathlib

OUTER_ID = "ST8-out"
TOP_ID = "ST8-top"

# Patterns
DRAWER_KINDS_RE = re.compile(
    r"\s*<drawer [^>]*id=\"21\"[^>]*>.*?</drawer>", re.DOTALL)
DRAWER_SEL_RE = re.compile(
    r"\s*<drawer [^>]*id=\"137\"[^>]*>.*?</drawer>", re.DOTALL)

# The OASplitView (id=95) and its two children we need to extract.
OASPLIT_RE = re.compile(
    r"(?P<indent> *)<splitView [^>]*id=\"95\"[^>]*>.*?</splitView>",
    re.DOTALL)
# Extract scrollView id=63 (files outline) and customView id=30 (treemap)
# from inside OASplitView. These are well-isolated blocks: the files
# outline has nested subviews but no other scrollView/customView at its
# own level besides itself within OASplitView's <subviews>.
SCROLL63_RE = re.compile(
    r" *<scrollView [^>]*id=\"63\"[^>]*>.*?</scrollView>", re.DOTALL)
TREEMAP30_RE = re.compile(
    r" *<customView [^>]*id=\"30\"[^>]*>.*?</customView>", re.DOTALL)

# Top-level customView id=24 (the kinds-table content) gets moved into
# the new top-right split pane.
KINDS_VIEW_RE = re.compile(
    r"\s*<customView id=\"24\"[^>]*>.*?</customView>", re.DOTALL)

# Owner connections
DRAWER_OUTLET_RE = re.compile(
    r'\s*<outlet property="_(kinds|selectionList)Drawer"[^/]*/>')
SPLITTER_OUTLET_RE = re.compile(
    r'(<outlet property="_splitter" destination=")[^"]+(")')
OWNER_CONN_RE = re.compile(
    r'(<customObject id="-2"[^>]*customClass="MainWindowController">\s*'
    r'<connections>)(.*?)(</connections>)',
    re.DOTALL)
NEW_OUTLETS_INSERT = """\
                <outlet property="_kindsTopSplit" destination="ST8-top" id="ST8-c1"/>
                <outlet property="_kindsPaneView" destination="50" id="ST8-c2"/>
                <outlet property="_selectionListPaneView" destination="138" id="ST8-c3"/>
"""

# Strip <point key="canvasLocation"> from moved customViews (no longer
# top-level so canvas position is meaningless).
CANVAS_LOC_RE = re.compile(r"\s*<point key=\"canvasLocation\"[^/]*/>")


def current_indent(block: str) -> int:
    first = block.split("\n", 1)[0]
    return len(first) - len(first.lstrip(" "))


def reindent(block: str, target: int) -> str:
    """Set indentation of every non-empty line so it starts at `target`."""
    cur = current_indent(block)
    if cur == target:
        return block
    if target > cur:
        pad = " " * (target - cur)
        return "\n".join(pad + ln if ln.strip() else ln
                         for ln in block.split("\n"))
    drop = cur - target
    out = []
    for ln in block.split("\n"):
        if ln.startswith(" " * drop):
            out.append(ln[drop:])
        else:
            out.append(ln.lstrip(" "))
    return "\n".join(out)


def main(path: str) -> None:
    p = pathlib.Path(path)
    src = p.read_text()

    # ---- 1. capture blocks we need to relocate ----
    m_oasplit = OASPLIT_RE.search(src)
    if not m_oasplit:
        sys.exit("error: could not locate <splitView id=\"95\">")
    oasplit_block = m_oasplit.group(0)
    outer_indent = m_oasplit.group("indent")  # e.g. 20 spaces

    inside = oasplit_block
    m_scroll = SCROLL63_RE.search(inside)
    m_treemap = TREEMAP30_RE.search(inside)
    if not (m_scroll and m_treemap):
        sys.exit("error: could not locate id=63 / id=30 inside OASplitView")
    scroll_block = m_scroll.group(0)
    treemap_block = m_treemap.group(0)

    m_kinds = KINDS_VIEW_RE.search(src)
    if not m_kinds:
        sys.exit("error: could not locate top-level <customView id=\"24\">")
    kinds_block_full = m_kinds.group(0).strip("\n")
    kinds_block_full = CANVAS_LOC_RE.sub("", kinds_block_full)
    # Unwrap: pull the inner <scrollView id="50"> out of the customView id=24
    # wrapper and use IT directly as the kinds pane. The customView added a
    # second layer that didn't line its scrollView up with the files-outline
    # scrollView in the sibling pane, causing the header to render at a
    # different position. With both panes being scrollViews directly under
    # the split, header alignment matches.
    m_kinds_scroll = re.search(
        r' *<scrollView [^>]*id="50"[^>]*>.*?</scrollView>',
        kinds_block_full, re.DOTALL)
    if not m_kinds_scroll:
        sys.exit("error: could not locate <scrollView id=\"50\"> inside customView id=\"24\"")
    kinds_block = m_kinds_scroll.group(0).strip("\n")

    # ---- 2. build the new outer/top splitView XML ----
    # Outer frame inherits OASplitView's original location/size:
    #   x=20, y=65, w=532, h=436   (inside contentView 572×521)
    # Outer is vertical=NO so it splits top/bottom.
    #   40% top / 60% bottom of 436 with 2pt divider:
    #     bottom pane: y=0,  h=260
    #     divider at y=260, height=2
    #     top pane:    y=262,h=174
    # Top split is vertical=YES so it splits L/R:
    #   35% files / 65% kinds of 532 with 2pt divider:
    #     left pane:  x=0,   w=185
    #     divider at  x=185, w=2
    #     right pane: x=187, w=345
    # We re-indent the moved blocks to their new positions.
    scroll_inner = reindent(scroll_block, len(outer_indent) + 16)
    kinds_inner = reindent(kinds_block, len(outer_indent) + 16)
    treemap_inner = reindent(treemap_block, len(outer_indent) + 8)

    # Adjust the moved blocks' frame rects to fit their new pane bounds.
    # We rewrite only the FIRST <rect key="frame" .../> inside each block
    # (which is the block's own frame; nested subviews keep their frames
    # and lay out via autoresizing).
    def replace_first_frame(block: str, x: float, y: float, w: float, h: float) -> str:
        return re.sub(
            r'<rect key="frame"[^/]*/>',
            f'<rect key="frame" x="{x}" y="{y}" width="{w}" height="{h}"/>',
            block, count=1)

    # New default window geometry: 1000×700 (was 572×521).
    # 10pt margins on the sides, 56pt bottom strip (status bar + 2 text
    # labels), 24pt top margin so the table column headers don't hug the
    # title bar.
    # Outer split:  x=10  y=56  w=980  h=620
    # Bottom pane (treemap):                            w=980  h=370
    # Divider (paneSplitter, 10pt):                     y=370  h=10
    # Top pane (inner split):           x=0   y=380     w=980  h=240
    #   files:  x=0    y=0  w=590  h=240   (~60%)
    #   divider:x=590  w=10
    #   kinds:  x=600  y=0  w=380  h=240   (~40% — fits Color/Kind/Size/Files
    #                                       with their natural numeric widths)
    scroll_inner = replace_first_frame(scroll_inner, 0, 0, 590, 240)
    kinds_inner = replace_first_frame(kinds_inner, 600, 0, 380, 240)
    treemap_inner = replace_first_frame(treemap_inner, 0, 0, 980, 370)

    # (kinds_block is now the bare scrollView id=50, no customView wrapper.
    # Its frame was just re-written by replace_first_frame above so it
    # already matches the pane.)

    # paneSplitter divider on both axes — the chunky dotted bar.
    # Reduced left/right margin (10). Bottom strip = 48pt (status bar 22 +
    # name label + size label tucked tight). Split sits above at y=48 to
    # leave 4pt below the lowest text row's top edge.
    new_split = f"""\
{outer_indent}<splitView dividerStyle="paneSplitter" fixedFrame="YES" vertical="NO" translatesAutoresizingMaskIntoConstraints="NO" id="{OUTER_ID}" userLabel="MainSplit_TopBottom">
{outer_indent}    <rect key="frame" x="10" y="56" width="980" height="620"/>
{outer_indent}    <autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
{outer_indent}    <subviews>
{outer_indent}        <splitView dividerStyle="paneSplitter" fixedFrame="YES" vertical="YES" translatesAutoresizingMaskIntoConstraints="NO" id="{TOP_ID}" userLabel="TopSplit_FilesKinds">
{outer_indent}            <rect key="frame" x="0.0" y="380" width="980" height="240"/>
{outer_indent}            <autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
{outer_indent}            <subviews>
{scroll_inner}
{kinds_inner}
{outer_indent}            </subviews>
{outer_indent}            <holdingPriorities>
{outer_indent}                <real value="250"/>
{outer_indent}                <real value="250"/>
{outer_indent}            </holdingPriorities>
{outer_indent}        </splitView>
{treemap_inner}
{outer_indent}    </subviews>
{outer_indent}    <holdingPriorities>
{outer_indent}        <real value="250"/>
{outer_indent}        <real value="250"/>
{outer_indent}    </holdingPriorities>
{outer_indent}</splitView>"""

    # ---- 3. mutate the buffer in safe order ----
    out = src

    # Owner connections: drop drawer outlets, repoint _splitter, add new
    m_owner = OWNER_CONN_RE.search(out)
    if not m_owner:
        sys.exit("error: could not locate File's Owner connections")
    inner = m_owner.group(2)
    if "_kindsTopSplit" in inner:
        sys.exit("error: owner connections already contain new outlets "
                 "(was this xib already reshaped?)")
    inner = DRAWER_OUTLET_RE.sub("", inner)
    inner = SPLITTER_OUTLET_RE.sub(r"\g<1>" + OUTER_ID + r"\g<2>", inner)
    inner = inner.rstrip() + "\n" + NEW_OUTLETS_INSERT + "            "
    out = out[:m_owner.start(2)] + inner + out[m_owner.end(2):]

    # Remove the two drawers
    out, n = DRAWER_KINDS_RE.subn("", out, count=1)
    if n != 1:
        sys.exit("error: did not remove <drawer id=\"21\">")
    out, n = DRAWER_SEL_RE.subn("", out, count=1)
    if n != 1:
        sys.exit("error: did not remove <drawer id=\"137\">")

    # Remove top-level customView id=24 FIRST (before we re-insert it
    # inside the new splitView). Top-level id=138 stays untouched.
    out, n = KINDS_VIEW_RE.subn("", out, count=1)
    if n != 1:
        sys.exit("error: did not remove top-level <customView id=\"24\">")

    # Replace OASplitView (id=95) with the new nested split structure.
    out, n = OASPLIT_RE.subn(lambda m: new_split, out, count=1)
    if n != 1:
        sys.exit("error: did not replace <splitView id=\"95\">")

    # Bottom-strip text labels: tighten layout, both labels small-system
    # font. Layout (after installStatusBar shifts everything up by 22):
    #   y=3..19  status bar (programmatic)
    #   y=22..36 file size (small font, 14pt tall)
    #   y=38..52 file name (small font, 14pt tall)
    #   y=70..   outer split (after +22 shift from y=48 in xib)
    # In the xib these are pre-shift so we use y=20 / y=36 / y=48.
    def replace_textfield_block(buf: str, field_id: str, new_y: int,
                                new_height: int, use_small_font: bool) -> str:
        # Match the entire <textField id="N"> ... </textField>.
        pat = re.compile(
            r'(<textField [^>]*id="' + field_id + r'"[^>]*>)'
            r'(.*?)'
            r'(</textField>)', re.DOTALL)
        m = pat.search(buf)
        if not m:
            return buf
        head, body, tail = m.group(1), m.group(2), m.group(3)
        # rewrite the first <rect key="frame" .../> inside
        body = re.sub(
            r'<rect key="frame"[^/]*/>',
            f'<rect key="frame" x="17" y="{new_y}" width="538" height="{new_height}"/>',
            body, count=1)
        if use_small_font:
            body = re.sub(
                r'<font key="font" metaFont="system"/>',
                '<font key="font" metaFont="smallSystem"/>',
                body, count=1)
        return buf[:m.start()] + head + body + tail + buf[m.end():]

    # Bottom labels (post-shift positions; pre-shift here):
    #   file size  y=22..36 (small font)
    #   file name  y=38..52 (small font, was system)
    # Outer split bottom is at y=56 → 4pt gap above file name top.
    out = replace_textfield_block(out, "45", 22, 14, use_small_font=False)
    out = replace_textfield_block(out, "33", 38, 14, use_small_font=True)

    # Widen the file-name and file-size labels to span the larger window
    # contentView (1000 wide minus 17pt left/right inset = 966).
    out = re.sub(
        r'(<textField [^>]*id="(?:33|45)"[^>]*>\s*\n\s*)<rect key="frame" x="17" y="(\d+)" width="\d+" height="(\d+)"/>',
        r'\g<1><rect key="frame" x="17" y="\g<2>" width="966" height="\g<3>"/>',
        out)

    # Bump the window's contentRect and contentView frame from 572×521
    # (the default we inherited) to 1000×700 so first launch shows a
    # generously sized window. Autosave preserves user resizes after that.
    out = re.sub(
        r'<rect key="contentRect" x="(\d+)" y="(\d+)" width="572" height="521"/>',
        r'<rect key="contentRect" x="\g<1>" y="\g<2>" width="1000" height="700"/>',
        out, count=1)
    out = re.sub(
        r'(<view key="contentView" id="23">\s*\n\s*)<rect key="frame" x="0.0" y="0.0" width="572" height="521"/>',
        r'\g<1><rect key="frame" x="0.0" y="0.0" width="1000" height="700"/>',
        out, count=1)

    # Initial column widths for the flex column in each table, so on first
    # launch the Name (files outline) and Kind (kinds table) columns fill
    # the pane and the trailing numeric columns sit flush against the right
    # edge of the pane. dixConfigureColumns will preserve any user-saved
    # widths beyond these on subsequent launches.
    #
    # Files-outline pane is 590 wide; budget: size (~100) + vertical
    # scroller (~18) = 118. displayName gets 590 - 118 = 472.
    out = re.sub(
        r'<tableColumn identifier="displayName" editable="NO" width="\d+"',
        r'<tableColumn identifier="displayName" editable="NO" width="472"',
        out, count=1)
    # Kinds pane is 380 wide; budget: color(35) + size(~100) + fileCount(~100)
    # + scroller(~18) = 253. kindName gets 380 - 253 = 127.
    out = re.sub(
        r'<tableColumn identifier="kindName" editable="NO" width="\d+"',
        r'<tableColumn identifier="kindName" editable="NO" width="127"',
        out, count=1)

    p.write_text(out)
    print(f"rewrote: {p}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: stage8_reshape_treemap_xib.py <path-to-TreeMap.xib>")
    main(sys.argv[1])
