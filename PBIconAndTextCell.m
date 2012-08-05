//
//  PBIconAndTextCell.m
//  GitX
//
//  Created by Ciarán Walsh on 23/09/2008.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//
// Adopted from http://www.cocoadev.com/index.pl?NSTableViewImagesAndText

#import "PBIconAndTextCell.h"


@implementation PBIconAndTextCell
@synthesize image;


- (id)copyWithZone:(NSZone *)zone
{
	PBIconAndTextCell *cell = [super copyWithZone:zone];
	cell.image              = image;
	return cell;
}

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
	if (image) {

		NSSize imageSize = [image size];
		NSRect imageFrame = NSZeroRect;

		NSDivideRect(cellFrame, &imageFrame, &cellFrame, 3 + imageSize.width, NSMinXEdge);
		if ([self drawsBackground]) {
			[[self backgroundColor] set];
			NSRectFill(imageFrame);
		}

		imageFrame.origin.x += 3;
		imageFrame.size = imageSize;
		imageFrame.origin.y += ceil((cellFrame.size.height - imageFrame.size.height) / 2);

 		[image drawInRect: imageFrame
				 fromRect: NSZeroRect
				operation: NSCompositeSourceOver
				 fraction: 1.0f
		   respectFlipped: YES
					hints: nil];
	}
	[super drawWithFrame:cellFrame inView:controlView];
}

- (NSSize)cellSize
{
	NSSize cellSize = [super cellSize];
	cellSize.width += (image ? [image size].width : 0) + 3;
	return cellSize;
}

@end
