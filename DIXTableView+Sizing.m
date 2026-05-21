//
//  DIXTableView+Sizing.m
//  Disk Inventory Z
//

#import "DIXTableView+Sizing.h"

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
// Reinforce the settings on every draw -- the binding machinery occasionally
// flips them back between row updates.
- (void) drawInteriorWithFrame: (NSRect) cellFrame inView: (NSView*) controlView
{
    [self setLineBreakMode: NSLineBreakByTruncatingTail];
    [self setUsesSingleLineMode: YES];
    [self setWraps: NO];
    [super drawInteriorWithFrame: cellFrame inView: controlView];
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

        if ( [numericIdentifiers containsObject: [col identifier]] )
        {
            // 2) Numeric (size / count) columns: clamp width to a tight range
            //    around the "1234.5 GB" natural width. min == max would forbid
            //    user resize, so leave a small band; max == natural+60 means
            //    AppKit's column autoresize never silently steals space here
            //    no matter how wide the table grows.
            CGFloat natural = MAX([col minWidth], numericContentWidth);
            CGFloat width   = MAX(natural, [col width]);  // honour wider user-saved widths
            [col setWidth: width];
            [col setMinWidth: natural];
            [col setMaxWidth: natural + 60];
            [col setResizingMask: NSTableColumnUserResizingMask];
        }
        else if ( col == flexibleColumn )
        {
            // 3) Name / outline / kind column: truncate with ellipsis and
            //    absorb extra width. If the column's data cell is exactly
            //    NSTextFieldCell (the IB default), swap it for our subclass
            //    that bakes in tail-truncation -- relying on lineBreakMode
            //    being set on the existing cell isn't reliable when bindings
            //    are in play (e.g. the file-kinds drawer's Kind column).
            //
            //    Custom data cells (ImageAndTextCell on the outline view's
            //    first column, and on the SelectionListTableController's
            //    displayName column where it draws name+icon side-by-side)
            //    must be preserved -- swapping them would lose the icon and
            //    the cell's custom -drawWithFrame: behaviour. For those we
            //    just nudge lineBreakMode/singleLineMode on the existing
            //    cell; truncation works there because those columns aren't
            //    bindings-managed.
            id dataCell = [col dataCell];
            BOOL isPlainTextCell = ( [dataCell class] == [NSTextFieldCell class] );

            if ( isPlainTextCell )
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
