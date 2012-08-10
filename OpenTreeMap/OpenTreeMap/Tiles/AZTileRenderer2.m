//
//  AZTileRenderer2.m
//  OpenTreeMap
//
//  Created by Adam Hinz on 8/8/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "AZTileRenderer2.h"
#import "AZPointParser.h"
#import "AZTile.h"
#import "AZTiler.h"

@implementation AZTileRenderer2

+(AZRenderedTile *)drawTile:(AZTile *)tile renderedTile:(AZRenderedTile *)rendered filters:(OTMFilters *)filters {
    if (rendered == nil) {
        rendered = [[AZRenderedTile alloc] init];
    }

    CGSize frameSize = CGSizeMake(256, 256);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, // Empty data pointer
                                                 256, // 256x256
                                                 256, 
                                                 8,  // 8 bits per channel
                                                 4 * 256, // 256 pixels per row x 4 bytes per pixel
                                                 colorSpace,
                                                 kCGImageAlphaPremultipliedFirst);
    CGColorSpaceRelease(colorSpace);

    // If there is no image, then we start be drawing the main points
    if (rendered.image == nil) {
        [self drawImage:tile.points 
              zoomScale:tile.zoomScale
                xOffset:0
                yOffset:0
                context:context
                filters:filters];
    } else { // Otherwise, draw the image
        CGContextDrawImage(context, CGRectMake(0,0,256,256), rendered.image.CGImage);
    }

    for(AZDirection dir in [[tile borderTiles] allKeys]) {
        // Directions only need to be drawn if they are in the pending list
        if ([rendered.pendingEdges containsObject:dir]) {
            [rendered.pendingEdges removeObject:dir];

            CGFloat xoff = 0.0f, yoff = 0.0f;
            if ([dir isEqualToString:kAZNorth]) {     xoff = 0.0f;  yoff = -1.0; }
            if ([dir isEqualToString:kAZNorthEast]) { xoff = 1.0f;  yoff = -1.0; }
            if ([dir isEqualToString:kAZEast]) {      xoff = 1.0f;  yoff = 0.0; }
            if ([dir isEqualToString:kAZSouthEast]) { xoff = 1.0f;  yoff = 1.0; }
            if ([dir isEqualToString:kAZSouth]) {     xoff = 0.0f;  yoff = 1.0; }
            if ([dir isEqualToString:kAZSouthWest]) { xoff = -1.0f; yoff = 1.0; }
            if ([dir isEqualToString:kAZWest]) {      xoff = -1.0f; yoff = 0.0; }
            if ([dir isEqualToString:kAZNorthWest]) { xoff = -1.0f; yoff = -1.0; }
            xoff *= 256.0;
            yoff *= -256.0;

            [self drawImage:[[tile borderTiles] objectForKey:dir]
                  zoomScale:tile.zoomScale
                    xOffset:xoff
                    yOffset:yoff
                    context:context
                    filters:filters];        

        }
    }
            

    // [[UIColor redColor] setStroke];
    // CGContextStrokeRect(UIGraphicsGetCurrentContext(), CGRectMake(0,0,256,256));

    CGImageRef cimage = CGBitmapContextCreateImage(context);
    UIImage* image = [UIImage imageWithCGImage:cimage];

    CGContextRelease(context);

    rendered.image = image;
    return rendered;
}

+(void)drawImage:(AZPointerArrayWrapper *)points
       zoomScale:(MKZoomScale)zoomScale
         xOffset:(CGFloat)xoffset
         yOffset:(CGFloat)yoffset
         context:(CGContextRef)context
         filters:(OTMFilters *)filters {

    NSArray *stampArray = [self stamps];

    // Drawing options.
    // If [filters active]:
    //    if [bit filters]:
    //       if point->style & filterbits > 0:
    //          stamp = HighLightStamp
    //       else
    //          stamp = nil
    //    else
    //          stamp = HighLightStamp
    // else:
    //     normal plot

    int baseScale = 18 + log2f(zoomScale); // OSM 18 level scale
    baseScale = MIN(MAX(baseScale, kAZTileRendererStampFirstLevel), 18);
    NSUInteger regularTreeIdx = baseScale - kAZTileRendererStampFirstLevel;
    NSUInteger plotIdx = baseScale - kAZTileRendererStampFirstLevel + kAZTileRendererStampOffsetPlot;
    NSUInteger searchIdx = baseScale - kAZTileRendererStampFirstLevel + kAZTileRendererStampOffsetHighlight;

    CGImageRef plotStamp = [[stampArray objectAtIndex:plotIdx] CGImage];
    CGImageRef treeStamp = [[stampArray objectAtIndex:regularTreeIdx] CGImage];
    CGImageRef searchStamp = [[stampArray objectAtIndex:searchIdx] CGImage];

    BOOL filtersActive = filters != nil;
    BOOL bitFiltersActive = [filters standardFiltersActive];
    uint8_t filterBits = filters.missingTree | (filters.missingDBH << 1) | (filters.missingSpecies << 2);

    size_t h = 0;
    size_t w = 0;

    CGImageRef stamp;

    for(int i=0;i<points.length;i++) {
        stamp = NULL;
        AZPoint *p = points.pointer[i];
        
        if (filtersActive) {
            if (bitFiltersActive) {
                // Invert from present to missing and
                // mask by '111' since we only care about
                // those three bits
                if ((((~p->style) & 0x6) & filterBits) > 0) { 
                    stamp = searchStamp;
                } else {
                    stamp = NULL;
                }
            } else {
                stamp = searchStamp;
            }
        } else {
            if ((p->style & 0x1) == 0x1) {
                stamp = treeStamp;
            } else {
                stamp = plotStamp;
            }
        }

        if (stamp != NULL) {
            w = CGImageGetWidth(stamp);
            h = CGImageGetHeight(stamp);
            CGRect baseRect = CGRectMake(-((CGFloat)w) / 2.0f,
                                         -((CGFloat)h) / 2.0f,
                                         w, h);
   
            CGRect rect = CGRectOffset(baseRect, p->xoffset + xoffset, 255 - p->yoffset + yoffset);

            CGContextDrawImage(context, rect, stamp);
        }
    }
}

+(UIImage *)mangleStamp:(UIImage *)image {
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGSize size = image.size;
    CGContextRef context = CGBitmapContextCreate(NULL, // Empty data pointer
                                                 size.width, // 256x256
                                                 size.height, 
                                                 8,  // 8 bits per channel
                                                 4 * size.width, // 256 pixels per row x 4 bytes per pixel
                                                 colorSpace,
                                                 kCGImageAlphaPremultipliedFirst);
    CGColorSpaceRelease(colorSpace);

    CGContextDrawImage(context, CGRectMake(0,0,size.width,size.height), image.CGImage);

    CGImageRef cimage = CGBitmapContextCreateImage(context);
    image = [UIImage imageWithCGImage:cimage];

    CGContextRelease(context);

    return image;
}

+(NSArray *)stamps {
    static NSMutableArray *stamps = nil;
    if (!stamps) {
        stamps = [NSMutableArray array];

        // Stamp objects start at Zoom Level 10
        // Regular trees
        [stamps addObject:[self mangleStamp:[UIImage imageNamed:@"tree_zoom1"]]]; // Level 10
        [stamps addObject:[self mangleStamp:[UIImage imageNamed:@"tree_zoom1"]]]; // Level 11
        [stamps addObject:[self mangleStamp:[UIImage imageNamed:@"tree_zoom3"]]]; // Level 12
        [stamps addObject:[self mangleStamp:[UIImage imageNamed:@"tree_zoom3"]]]; // Level 13
        [stamps addObject:[self mangleStamp:[UIImage imageNamed:@"tree_zoom5"]]]; // Level 14
        [stamps addObject:[self mangleStamp:[UIImage imageNamed:@"tree_zoom5"]]]; // Level 15
        [stamps addObject:[self mangleStamp:[UIImage imageNamed:@"tree_zoom6"]]]; // Level 16
        [stamps addObject:[self mangleStamp:[UIImage imageNamed:@"tree_zoom7"]]]; // Level 17
        [stamps addObject:[self mangleStamp:[UIImage imageNamed:@"tree_zoom7"]]]; // Level 18

        // Plots
        [stamps addObject:[self mangleStamp:[UIImage imageNamed:@"tree_zoom1_plot"]]]; // Level 10
        [stamps addObject:[self mangleStamp:[UIImage imageNamed:@"tree_zoom1_plot"]]]; // Level 11
        [stamps addObject:[self mangleStamp:[UIImage imageNamed:@"tree_zoom3_plot"]]]; // Level 12
        [stamps addObject:[self mangleStamp:[UIImage imageNamed:@"tree_zoom3_plot"]]]; // Level 13
        [stamps addObject:[self mangleStamp:[UIImage imageNamed:@"tree_zoom5_plot"]]]; // Level 14
        [stamps addObject:[self mangleStamp:[UIImage imageNamed:@"tree_zoom5_plot"]]]; // Level 15
        [stamps addObject:[self mangleStamp:[UIImage imageNamed:@"tree_zoom6_plot"]]]; // Level 16
        [stamps addObject:[self mangleStamp:[UIImage imageNamed:@"tree_zoom7_plot"]]]; // Level 17
        [stamps addObject:[self mangleStamp:[UIImage imageNamed:@"tree_zoom7_plot"]]]; // Level 18

        // Highlight (same for all levels)
        [stamps addObject:[self mangleStamp:[UIImage imageNamed:@"tree_zoom7"]]]; // Level 10
        [stamps addObject:[self mangleStamp:[UIImage imageNamed:@"tree_zoom7"]]]; // Level 11
        [stamps addObject:[self mangleStamp:[UIImage imageNamed:@"tree_zoom7"]]]; // Level 12
        [stamps addObject:[self mangleStamp:[UIImage imageNamed:@"tree_zoom7"]]]; // Level 13
        [stamps addObject:[self mangleStamp:[UIImage imageNamed:@"tree_zoom7"]]]; // Level 14
        [stamps addObject:[self mangleStamp:[UIImage imageNamed:@"tree_zoom7"]]]; // Level 15
        [stamps addObject:[self mangleStamp:[UIImage imageNamed:@"tree_zoom7"]]]; // Level 16
        [stamps addObject:[self mangleStamp:[UIImage imageNamed:@"tree_zoom7"]]]; // Level 17
        [stamps addObject:[self mangleStamp:[UIImage imageNamed:@"tree_zoom7"]]]; // Level 18


    }

    return stamps;
}
    
@end
