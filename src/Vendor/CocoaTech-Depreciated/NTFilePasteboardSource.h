//
//  NTFilePasteboardSource.h
//  Path Finder
//
//  Created by Steve Gehrman on Sun Feb 02 2003.
//  Copyright (c) 2003 CocoaTech. All rights reserved.
//

// NTFilePasteboardSource isn't included in the CocoaTech Frameworks any more
// (and there is no replacement class either).
// So I copied this class to the Disk Inventory Z project.

@class NTFileDesc;

@interface NTFilePasteboardSource : NSObject <NSPasteboardItemDataProvider>
{
    NSArray<NSURL*> *_URLs;
}

+ (NTFilePasteboardSource*)files:(NSArray<NSURL*> *)URLs toPasteboard:(NSPasteboard *)pboard types:(NSArray<NSPasteboardType> *)types;
+ (NTFilePasteboardSource*)file:(NSURL *)URL toPasteboard:(NSPasteboard *)pboard types:(NSArray<NSPasteboardType> *)types;

+ (NSArray<NSPasteboardType>*)defaultTypes;
+ (NSArray<NSPasteboardType>*)imageTypes;

@end
