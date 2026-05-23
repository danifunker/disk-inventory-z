//
//  DIXTableView+Sizing.m
//  Disk Inventory Z
//

#import "DIXTableView+Sizing.h"
#import "ImageAndTextCell.h"

// NSTableHeaderView's default rendering uses a translucent material so the
// window's vibrancy bleeds through. In the main outline view that produces
// a visual where the row immediately below the header looks like it sits
// *under* the header (because it does -- it just shows through). The right-
// side file-kinds drawer doesn't show this because its background is
// already opaque. Painting an opaque windowBackground here matches the
// drawer's look without disturbing the system header style on top.
@interface DIXOpaqueTableHeaderView : NSTableHeaderView
@end

@implementation DIXOpaqueTableHeaderView
- (BOOL) isOpaque { return YES; }
- (void) drawRect: (NSRect) dirtyRect
{
    [[NSColor windowBackgroundColor] setFill];
    NSRectFill(dirtyRect);
    [super drawRect: dirtyRect];
}
@end

// NSTextFieldCell subclass that always tail-truncates with an ellipsis.
// Setting lineBreakMode in -tableView:willDisplayCell: isn't reliable on
// cell-based tables with bindings: the bindings machinery can replace the
// effective cell per draw, so the truncation never sticks. By baking the
// behaviour into a subclass and assigning it as the column's dataCell, we
// ensure the cell instance that actually draws is the one we configured.
@interface DIXTruncatingTextFieldCell : NSTextFieldCell
@end

@implementation DIXTruncatingTextFieldCell
- (instancetype) initTextCell: (NSString*) string
{
    self = [super initTextCell: string];
    if ( self != nil )
    {
        [self setLineBreakMode: NSLineBreakByTruncatingTail];
        [self setUsesSingleLineMode: YES];
        [self setWraps: NO];
        [self setScrollable: NO];
        [self setTruncatesLastVisibleLine: YES];
    }
    return self;
}
- (instancetype) initWithCoder: (NSCoder*) coder
{
    self = [super initWithCoder: coder];
    if ( self != nil )
    {
        [self setLineBreakMode: NSLineBreakByTruncatingTail];
        [self setUsesSingleLineMode: YES];
        [self setWraps: NO];
        [self setScrollable: NO];
        [self setTruncatesLastVisibleLine: YES];
    }
    return self;
}
// Draw the string ourselves so truncation is GUARANTEED, regardless of how
// the underlying value was set on the cell. NSTextFieldCell's own drawing
// uses NSStringDrawing internally but its respect for lineBreakMode varies
// depending on whether the bound value is a plain NSString (honoured) or an
// NSAttributedString lacking a paragraph style (ignored). By forming our
// own attributed string with NSParagraphStyle.lineBreakMode = .byTruncating
// Tail and drawing it with NSStringDrawingTruncatesLastVisibleLine, we get
// the ellipsis irrespective of what the binding feeds in.
- (void) drawInteriorWithFrame: (NSRect) cellFrame inView: (NSView*) controlView
{
    [self setLineBreakMode: NSLineBreakByTruncatingTail];
    [self setUsesSingleLineMode: YES];
    [self setWraps: NO];

    NSAttributedString *attr = [self attributedStringValue];
    if ( [attr length] == 0 )
    {
        [super drawInteriorWithFrame: cellFrame inView: controlView];
        return;
    }

    NSRect titleRect = [self titleRectForBounds: cellFrame];
    // NSTextFieldCell's title rect already includes the standard insets but
    // some cells return the bare bounds; clamp to cellFrame just in case.
    if ( NSIsEmptyRect(titleRect) )
        titleRect = NSInsetRect(cellFrame, 2, 0);

    // Vertical centering for the single line: measure once and place it.
    CGFloat lineHeight = [attr size].height;
    CGFloat yOffset = floor((NSHeight(titleRect) - lineHeight) / 2);
    titleRect.origin.y += yOffset;
    titleRect.size.height = lineHeight;

    [attr drawWithRect: titleRect
               options: NSStringDrawingUsesLineFragmentOrigin
                      | NSStringDrawingTruncatesLastVisibleLine];
}

// Cocoa Bindings can feed an attributed string into the cell (via
// -setObjectValue: with an NSAttributedString, or via the value transformer).
// When that happens, NSAttributedString -drawWithRect:options: -- which our
// -drawInteriorWithFrame: below uses -- only respects the attributes embedded
// in the string, with no fallback to the cell's font / textColor. We inject:
//   * a paragraph style with NSLineBreakByTruncatingTail (so the ellipsis
//     actually renders), and
//   * a foreground colour anywhere the string is missing one (so that an
//     appearance-aware system colour like controlTextColor is honoured;
//     without this, dark-mode windows show the volume-name transformer's
//     attributed strings in black because the transformer never sets a
//     colour).
- (NSAttributedString*) attributedStringValue
{
    NSAttributedString *base = [super attributedStringValue];
    if ( [base length] == 0 )
        return base;

    NSMutableParagraphStyle *style = [[[NSMutableParagraphStyle alloc] init] autorelease];
    [style setLineBreakMode: NSLineBreakByTruncatingTail];

    NSMutableAttributedString *result = [[base mutableCopy] autorelease];
    NSRange fullRange = NSMakeRange(0, [result length]);
    [result addAttribute: NSParagraphStyleAttributeName value: style range: fullRange];

    NSColor *fallbackColor = [self textColor] ?: [NSColor controlTextColor];
    [result enumerateAttribute: NSForegroundColorAttributeName
                       inRange: fullRange
                       options: 0
                    usingBlock: ^(id existing, NSRange range, BOOL *stop)
    {
        if ( existing == nil )
            [result addAttribute: NSForegroundColorAttributeName
                           value: fallbackColor
                           range: range];
    }];
    return result;
}
@end

@implementation NSTableView (DIXColumnSizing)

- (void) dixConfigureColumnsWithNumericIdentifiers: (NSArray<NSString*>*) numericIdentifiers
                                flexibleIdentifier: (NSString*) flexibleIdentifier
{
    // Representative width for a "1234.5 GB"-style value in the cell's font,
    // plus a small padding so the trailing unit isn't right against the cell
    // edge. This is the natural width every "numeric" column gets.
    NSFont *cellFont = [self font] ?: [NSFont systemFontOfSize: [NSFont systemFontSize]];
    NSDictionary *cellAttrs = @{ NSFontAttributeName: cellFont };
    const CGFloat numericContentWidth = ceil([@"1234.5 GB" sizeWithAttributes: cellAttrs].width) + 18;

    NSTableColumn *flexibleColumn = nil;
    if ( flexibleIdentifier != nil )
        flexibleColumn = [self tableColumnWithIdentifier: flexibleIdentifier];
    if ( flexibleColumn == nil && [self respondsToSelector: @selector(outlineTableColumn)] )
        flexibleColumn = [(NSOutlineView*)self outlineTableColumn];
    if ( flexibleColumn == nil && [[self tableColumns] count] > 0 )
        flexibleColumn = [self tableColumns][0];

    for ( NSTableColumn *col in [self tableColumns] )
    {
        // 1) Header text must always fit. Add ~16pt for sort indicator + padding.
        const CGFloat headerNatural = ceil([[col headerCell] cellSize].width) + 16;
        if ( [col minWidth] < headerNatural )
            [col setMinWidth: headerNatural];

        BOOL isNumeric  = [numericIdentifiers containsObject: [col identifier]];
        BOOL isFlexible = ( col == flexibleColumn );

        if ( isNumeric )
        {
            // Numeric (size / count) columns: clamp width to a tight range
            // around the "1234.5 GB" natural width. min == max would forbid
            // user resize, so leave a small band; max == natural+60 means
            // AppKit's column autoresize never silently steals space here
            // no matter how wide the table grows.
            CGFloat natural = MAX([col minWidth], numericContentWidth);
            CGFloat width   = MAX(natural, [col width]);  // honour wider user-saved widths
            [col setWidth: width];
            [col setMinWidth: natural];
            [col setMaxWidth: natural + 60];
            [col setResizingMask: NSTableColumnUserResizingMask];
        }
        else
        {
            // Any non-numeric text column: tail-truncate with an ellipsis. If
            // the column's data cell is some kind of NSTextFieldCell that
            // ISN'T one of the app's custom cells whose -drawWithFrame:
            // behaviour we must preserve (ImageAndTextCell draws name+icon
            // side-by-side on the outline view's first column and on the
            // selection list's Name column; replacing it would lose both),
            // swap it for DIXTruncatingTextFieldCell which draws the title
            // manually with NSStringDrawingTruncatesLastVisibleLine. For
            // custom cells we set lineBreakMode/usesSingleLineMode instead.
            //
            // The flex column additionally gets the autoresizing mask so it
            // absorbs extra width from the enclosing scroll view.
            id dataCell = [col dataCell];
            BOOL isReplaceableTextCell =
                [dataCell isKindOfClass: [NSTextFieldCell class]]
                && ![dataCell isKindOfClass: [ImageAndTextCell class]]
                && ![dataCell isKindOfClass: [DIXTruncatingTextFieldCell class]];

            if ( isReplaceableTextCell )
            {
                DIXTruncatingTextFieldCell *truncCell =
                    [[[DIXTruncatingTextFieldCell alloc] initTextCell: @""] autorelease];
                [truncCell setEditable:    [dataCell isEditable]];
                [truncCell setSelectable:  [dataCell isSelectable]];
                [truncCell setAlignment:   [dataCell alignment]];
                [truncCell setFont:        [dataCell font]];
                if ( [dataCell formatter] != nil )
                    [truncCell setFormatter: [dataCell formatter]];
                [col setDataCell: truncCell];
            }
            else if ( [dataCell respondsToSelector: @selector(setLineBreakMode:)] )
            {
                [dataCell setLineBreakMode: NSLineBreakByTruncatingTail];
                if ( [dataCell respondsToSelector: @selector(setUsesSingleLineMode:)] )
                    [dataCell setUsesSingleLineMode: YES];
            }

            if ( isFlexible )
                [col setResizingMask: NSTableColumnAutoresizingMask | NSTableColumnUserResizingMask];
        }
    }

    // 4) Only the first / outline column absorbs width changes. Together with
    //    each numeric column's max-width clamp above, this gives the layout
    //    we want without ever computing widths ourselves: AppKit grows the
    //    flexible column to fill, never steals from a clamped numeric.
    [self setColumnAutoresizingStyle: NSTableViewFirstColumnOnlyAutoresizingStyle];

    // 5) Replace the default translucent header view with an opaque one so
    //    rows scrolling under it can't visually bleed through.
    NSTableHeaderView *existing = [self headerView];
    if ( existing != nil && ![existing isKindOfClass: [DIXOpaqueTableHeaderView class]] )
    {
        DIXOpaqueTableHeaderView *opaque =
            [[[DIXOpaqueTableHeaderView alloc] initWithFrame: [existing frame]] autorelease];
        [self setHeaderView: opaque];
    }

}

@end
