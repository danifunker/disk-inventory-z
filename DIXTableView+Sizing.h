//
//  DIXTableView+Sizing.h
//  Disk Inventory Z
//
//  Copyright (C) 2026 Dani Sarfati.
//
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 3
//  of the License, or any later version.
//
//  Shared column-sizing logic for the app's table / outline views: ensure
//  header text never clips, give numeric (size / count) columns enough
//  width for a representative value, let the first / name column absorb
//  window-width changes and truncate long names with an ellipsis.
//

#import <Cocoa/Cocoa.h>

@interface NSTableView (DIXColumnSizing)

// Configure every column on this table view (or outline view) so:
//  - Each column's minWidth >= the natural width of its header text
//    (so resizing the window can't clip header titles).
//  - Columns whose identifier appears in `numericIdentifiers` get a
//    fixed width sized for a "1234.5 GB"-style representative value
//    and stop auto-resizing with the table.
//  - `flexibleIdentifier` (or, when nil, the outline column / first
//    table column) truncates long string values with an ellipsis and
//    is the only column that absorbs extra width when the table /
//    window resizes. Pass the identifier explicitly when the first
//    column is something small like a colour swatch and a different
//    column (Kind, Name) should be the one that fills.
//  - The table view's header view is replaced with an opaque variant
//    so content rows scrolling under it don't visually bleed through.
//
// Safe to call multiple times; subsequent calls only widen widths to
// keep currently-larger columns where the user dragged them.
- (void) dixConfigureColumnsWithNumericIdentifiers: (NSArray<NSString*>*) numericIdentifiers
                                flexibleIdentifier: (nullable NSString*) flexibleIdentifier;

@end
