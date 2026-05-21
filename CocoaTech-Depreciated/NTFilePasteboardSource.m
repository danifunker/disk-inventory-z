//
//  NTFilePasteboardSource.m
//  Path Finder
//
//  Created by Steve Gehrman on Sun Feb 02 2003.
//  Copyright (c) 2003 CocoaTech. All rights reserved.
//

#import "NTFilePasteboardSource.h"
#import "NSURL-Extensions.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

// SNG 666 add NSPICTPboardType

@interface NTFilePasteboardSource (Private)
- (NSArray<NSString*>*)pasteboardTypes:(NSArray<NSPasteboardType> *)types;
@end

@implementation NTFilePasteboardSource

- (id)initWithURLs:(NSArray<NSURL*>*)URLs;
{
    self = [super init];

    _URLs = [URLs retain];

    return self;
}

- (void)dealloc;
{
    [_URLs release];

    [super dealloc];
}

+ (NSArray<NSPasteboardType>*)defaultTypes;
{
    return [NSArray arrayWithObjects:
        NSPasteboardTypeTIFF,
        NSPasteboardTypePDF,
        (NSPasteboardType)@"com.adobe.encapsulated-postscript",

        NSPasteboardTypeRTF,
        NSPasteboardTypeRTFD,
        NSPasteboardTypeHTML,

        NSFileContentsPboardType,

        NSPasteboardTypeFileURL,
        NSPasteboardTypeString,
        nil];
}

+ (NSArray<NSPasteboardType>*)imageTypes;
{
    return [NSArray arrayWithObjects:
        NSPasteboardTypeTIFF,
        NSPasteboardTypePDF,
        (NSPasteboardType)@"com.adobe.encapsulated-postscript",
        nil];
}

+ (NTFilePasteboardSource*)file:(NSURL *)URL toPasteboard:(NSPasteboard *)pboard types:(NSArray<NSPasteboardType> *)types;
{
    return [NTFilePasteboardSource files:[NSArray<NSURL*> arrayWithObject:URL] toPasteboard:pboard types:types];
}

+ (NTFilePasteboardSource*)files:(NSArray<NSURL*> *)URLs toPasteboard:(NSPasteboard *)pboard types:(NSArray<NSPasteboardType> *)types;
{
    NTFilePasteboardSource* source = [[[NTFilePasteboardSource alloc] initWithURLs:URLs] autorelease];
    NSArray<NSPasteboardType>* pasteboardTypes = [source pasteboardTypes:types];

    if (pasteboardTypes)
    {
        // NSPasteboard provides the data lazily by calling the owner's
        // -pasteboard:provideDataForType: and retains the owner until the
        // pasteboard contents change.
        [pboard declareTypes:pasteboardTypes owner:source];
    }

    return source;
}

@end

@implementation NTFilePasteboardSource (Private)

- (NSArray<NSPasteboardType>*)pasteboardTypes:(NSArray<NSPasteboardType> *)types;
{
    if ([_URLs count])
    {
        NSURL* url = [_URLs objectAtIndex:0];

        // figure out what type of file the current selection is
        if (url)
        {
            NSMutableArray<NSPasteboardType> *pasteTypes = [NSMutableArray<NSPasteboardType> array];
            NSString* uti = [url UTI];
            
            for (NSString *type in types)
            {
                if ([type isEqualToString:NSPasteboardTypeFileURL])
                    [pasteTypes addObject:type];
                else if ([type isEqualToString:NSPasteboardTypeString])
                    [pasteTypes addObject:type];
                else if ([type isEqualToString:NSFileContentsPboardType])
                    [pasteTypes addObject:type];
                else if ([type isEqualToString:NSPasteboardTypeTIFF]) // we use the icon if not an image, so don't check isImage && [identifier isImage])
                    [pasteTypes addObject:type];
                else if ([type isEqualToString:NSPasteboardTypeRTF] && [uti isEqualToString: UTTypeRTF.identifier])
                    [pasteTypes addObject:type];
                else if ([type isEqualToString:NSPasteboardTypeRTFD] && [uti isEqualToString: UTTypeFlatRTFD.identifier])
                    [pasteTypes addObject:type];
                else if ([type isEqualToString:NSPasteboardTypeHTML] && [uti isEqualToString: UTTypeHTML.identifier])
                    [pasteTypes addObject:type];
                else if ([type isEqualToString:NSPasteboardTypePDF] && [uti isEqualToString: UTTypePDF.identifier])
                    [pasteTypes addObject:type];
            }

            if ([pasteTypes count])
                return pasteTypes;
        }
    }

    return nil;
}

- (void)pasteboard:(NSPasteboard *)pboard provideDataForType:(NSString *)type
{
    if (_URLs && [_URLs count])
    {
        NSURL* url = [_URLs objectAtIndex:0];

        if (url)
        {
            NSString* uti = [url UTI];

            if ([type isEqualToString:NSPasteboardTypeFileURL])
            {
                // NSPasteboardTypeFileURL holds a single file URL; the app only
                // ever drags/copies one item (single selection), so write the
                // first URL.
                [pboard setString:[url absoluteString] forType:NSPasteboardTypeFileURL];
            }
            else if ([type isEqualToString:NSPasteboardTypeString])
            {
                // set the path
                [pboard setString:[url path] forType:NSPasteboardTypeString];
            }
            else if ([type isEqualToString:NSFileContentsPboardType])
            {
                // write the contents
                [pboard writeFileContents:[url path]];
            }
            else if ([type isEqualToString:NSPasteboardTypeTIFF])
            {
                if ([uti isEqualToString: UTTypeTIFF.identifier])
                    [pboard setData:[NSData dataWithContentsOfFile:[url path]] forType:NSPasteboardTypeTIFF];
                else if ( [[UTType typeWithIdentifier: uti] conformsToType: UTTypeImage] )
                {
                    // open the image and return TIFFRepresentation
                    NSImage *image = [[[NSImage alloc] initWithContentsOfFile:[url path]] autorelease];

                    if (image)
                    {
                        NSData* data = [image TIFFRepresentation];

                        if (data)
                            [pboard setData:data forType:NSTIFFPboardType];
                    }
                }
                else // else send the icon
                {
#pragma warning "NTFilePasteBoardSource: providing file icon not implemented"
 /*                   // open the image and return TIFFRepresentation
                    NSImage* image = [NSImage iconRef:[[desc icon] iconRef] toImage:128 label:[desc label] select:NO];

                    if (image)
                    {
                        NSData* data = [image TIFFRepresentation];

                        if (data)
                            [pboard setData:data forType:NSPasteboardTypeTIFF];
                    }
 */
                }
            }
            else if ([type isEqualToString:NSPasteboardTypeRTF])
            {
                if ([uti isEqualToString: UTTypeRTF.identifier])
                    [pboard setData:[NSData dataWithContentsOfFile:[url path]] forType:NSPasteboardTypeRTF];
            }
            else if ([type isEqualToString:NSPasteboardTypeRTFD])
            {
                if ([uti isEqualToString: UTTypeFlatRTFD.identifier])
                {
                    NSFileWrapper *tempRTFDData = [[[NSFileWrapper alloc] initWithPath:[url path]] autorelease];
                    [pboard setData:[tempRTFDData serializedRepresentation] forType:NSPasteboardTypeRTFD];
                }
            }
            else if ([type isEqualToString:NSPasteboardTypeHTML])
            {
                if ([uti isEqualToString: UTTypeHTML.identifier])
                    [pboard setData:[NSData dataWithContentsOfFile:[url path]] forType:NSPasteboardTypeHTML];
            }
            else if ([type isEqualToString:NSPasteboardTypePDF])
            {
                if ([uti isEqualToString: UTTypePDF.identifier])
                    [pboard setData:[NSData dataWithContentsOfFile:[url path]] forType:NSPasteboardTypePDF];
            }
        }
    }
}

@end
