//
//  PBWebStashController.m
//
//  Created by David Catmull on 12-06-11.
//

#import "PBWebStashController.h"
#import "PBStashContentController.h"

@implementation PBWebStashController

@synthesize stashController;

- (void)selectCommit:(NSString *)sha
{
	[[stashController superController] selectCommitForSha:sha];
}

- (NSArray*) menuItemsForPath:(NSString*)path
{
	return [[stashController superController] menuItemsForPaths:@[path]];
}

- (NSArray*) chooseDiffParents:(NSArray *)parents
{
	return @[[parents lastObject]];
}

@end
