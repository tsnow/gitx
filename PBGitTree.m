//
//  PBGitTree.m
//  GitTest
//
//  Created by Pieter de Bie on 15-06-08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "PBGitTree.h"
#import "PBGitCommit.h"
#import "NSFileHandleExt.h"
#import "PBEasyPipe.h"
#import "PBEasyFS.h"

@implementation PBGitTree

@synthesize sha, path, repository, leaf, parent;
@synthesize filterPredicate;
@synthesize filteredChildren;

#pragma mark -
#pragma mark get/set

- (NSArray *) filteredChildren {
	if (!filteredChildren) {
		filteredChildren = [[NSMutableArray alloc] init];
		[filteredChildren addObjectsFromArray:self.children];
	}
	return filteredChildren;
}

- (void) setFilterPredicate:(NSPredicate *) newPredicate {
	if (newPredicate != filterPredicate) {
		filterPredicate = newPredicate;
		
		if (leaf) {
			return;
		}
		
		// initiate filtering
		[filteredChildren removeAllObjects];
		filteredChildren = [[NSMutableArray alloc] init];
		
		if (filterPredicate == nil) {
			[filteredChildren addObjectsFromArray:self.children];
		}

		for (id item in self.children) {
			[item setFilterPredicate:filterPredicate];
			if (filterPredicate) {
				if ([item leaf]) {
					if ([filterPredicate evaluateWithObject:item]) {
						[filteredChildren addObject:item];
					}
				} else {
					if ([[item filteredChildren] count] > 0) {
						[filteredChildren addObject:item];
					}
				}
			}
		}
	}
}

#pragma mark -

+ (PBGitTree*) rootForCommit:(id) commit
{
	PBGitCommit* c = commit;
	PBGitTree* tree = [[self alloc] init];
	tree.parent = nil;
	tree.leaf = NO;
	tree.sha = [c realSha];
	tree.repository = c.repository;
	tree.path = @"";
	return tree;
}

+ (PBGitTree*) treeForTree: (PBGitTree*) prev andPath: (NSString*) path;
{
	PBGitTree* tree = [[self alloc] init];
	tree.parent = prev;
	tree.sha = prev.sha;
	tree.repository = prev.repository;
	tree.path = path;
	return tree;
}

- init
{
	filteredChildren = nil;
	children = nil;
	localFileName = nil;
	leaf = YES;
	return self;
}

- (NSString*) refSpec
{
	return [NSString stringWithFormat:@"%@:%@", self.sha, self.fullPath];
}

- (BOOL) isLocallyCached
{
	NSFileManager* fs = [NSFileManager defaultManager];
	if (localFileName && [fs fileExistsAtPath:localFileName])
	{
		NSDate* mtime = [fs attributesOfItemAtPath:localFileName error: nil][NSFileModificationDate];
		if ([mtime compare:localMtime] == 0)
			return YES;
	}
	return NO;
}

- (BOOL)hasBinaryAttributes
{
	// First ask git check-attr if the file has a binary attribute custom set
	NSFileHandle *handle = [repository handleInWorkDirForArguments:@[@"check-attr", @"binary", [self fullPath]]];
	NSData *data = [handle readDataToEndOfFile];
	NSString *string = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];

	if (!string)
		return NO;
	string = [string stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];

	if ([string hasSuffix:@"binary: set"])
		return YES;

	if ([string hasSuffix:@"binary: unset"])
		return NO;

	// Binary state unknown, do a check on common filename-extensions
	for (NSString *extension in @[@".pdf", @".jpg", @".jpeg", @".png", @".bmp", @".gif", @".o"]) {
		if ([[self fullPath] hasSuffix:extension])
			return YES;
	}

	return NO;
}

- (NSString*) contents
{
	if (!leaf)
		return [NSString stringWithFormat:@"This is a tree with path %@", [self fullPath]];

	if ([self isLocallyCached]) {
		NSData *data = [NSData dataWithContentsOfFile:localFileName];
		NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
		if (!string)
			string = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
		return string;
	}
	
	return [repository outputForArguments:@[@"show", [self refSpec]]];
}

- (NSString *) blame:(NSError **)anError
{
	NSString *error=nil;
	NSString *res=nil;
	if (!leaf)
		error=[NSString stringWithFormat:@"This is a tree with path %@", [self fullPath]];
	
	if ([self hasBinaryAttributes])
		error=[NSString stringWithFormat:@"%@ appears to be a binary file of %lld bytes", [self fullPath], [self fileSize]];
	
	if ([self fileSize] > 52428800) // ~50MB
		error=[NSString stringWithFormat:@"%@ is too big to be displayed (%lld bytes)", [self fullPath], [self fileSize]];
	
	if(error==nil){
		res=[repository outputInWorkdirForArguments:@[@"blame", @"-p",  sha, @"--", [self fullPath]]];
	}else{
		if (anError != NULL) {
			*anError = [NSError errorWithDomain:@"blame" code:1 userInfo:@{NSLocalizedDescriptionKey: error}];
		}
	}
	
	return res;
}

- (NSString *) log:(NSString *)format error:(NSError **)anError
{
	NSString *error=nil;
	NSString *res=nil;
	if (!leaf)
		error=[NSString stringWithFormat:@"This is a tree with path %@", [self fullPath]];
	
	if(error==nil){
		res=[repository outputInWorkdirForArguments:@[@"log", [NSString stringWithFormat:@"--pretty=format:%@",format], @"--", [self fullPath]]];
	}else{
		if (anError != NULL) {
			*anError = [NSError errorWithDomain:@"log" code:1 userInfo:@{NSLocalizedDescriptionKey: error}];
		}
	}
	
	return res;
}

- (NSString *) diff:(NSString *)format error:(NSError **)anError
{
	NSString *error=nil;
	NSString *res=nil;
	if (!leaf)
		error=[NSString stringWithFormat:@"This is a tree with path %@", [self fullPath]];
	
	if ([self hasBinaryAttributes])
		error=[NSString stringWithFormat:@"%@ appears to be a binary file of %lld bytes", [self fullPath], [self fileSize]];
	
	if ([self fileSize] > 52428800) // ~50MB
		error=[NSString stringWithFormat:@"%@ is too big to be displayed (%lld bytes)", [self fullPath], [self fileSize]];
	
	if(error==nil){
		NSString *des=@"";
		if(format==@"p") {
			des=[NSString stringWithFormat:@"%@^",sha];
		}else if(format==@"h") {
			des=@"HEAD";
		}else{
			des=@"--";
		}
		res=[repository outputInWorkdirForArguments:@[@"diff", sha, des,[self fullPath]]];
		if ([res length]==0) {
			DLog(@"--%lu",[res length]);
			if (anError != NULL) {
				*anError = [NSError errorWithDomain:@"diff" code:1 userInfo:@{NSLocalizedDescriptionKey: @"No Diff"}];
			}
		}else{
			DLog(@"--%@",[res substringToIndex:80]);
		}
	}else{
		if (anError != NULL) {
			*anError = [NSError errorWithDomain:@"diff" code:1 userInfo:@{NSLocalizedDescriptionKey: error}];
		}
	}

	return res;
}

- (NSString *)textContents:(NSError **)anError
{
	NSString *error=nil;
	NSString *res=nil;
	if (!leaf)
		error=[NSString stringWithFormat:@"This is a tree with path %@", [self fullPath]];
	
	if ([self hasBinaryAttributes])
		error=[NSString stringWithFormat:@"%@ appears to be a binary file of %lld bytes", [self fullPath], [self fileSize]];
	
	if ([self fileSize] > 52428800) // ~50MB
		error=[NSString stringWithFormat:@"%@ is too big to be displayed (%lld bytes)", [self fullPath], [self fileSize]];
	
	if(error==nil){
		res = [self contents];
	}else{
		if (anError != NULL) {
			*anError = [NSError errorWithDomain:@"show" code:1 userInfo:@{NSLocalizedDescriptionKey: error}];
		}
	}

	return res;
}

- (long long)fileSize
{
	if (_fileSize)
		return _fileSize;

	NSFileHandle *handle = [repository handleForArguments:@[@"cat-file", @"-s", [self refSpec]]];
	NSString *sizeString = [[NSString alloc] initWithData:[handle readDataToEndOfFile] encoding:NSISOLatin1StringEncoding];

	if (!sizeString)
		_fileSize = -1;
	else
		_fileSize = [sizeString longLongValue];

	return _fileSize;
}

- (void) saveToFolder: (NSString *) dir
{
	NSString* newName = [dir stringByAppendingPathComponent:path];

	if (leaf) {
		NSFileHandle* handle = [repository handleForArguments:@[@"show", [self refSpec]]];
		NSData* data = [handle readDataToEndOfFile];
		[data writeToFile:newName atomically:YES];
	} else { // Directory
		[[NSFileManager defaultManager] createDirectoryAtPath:newName withIntermediateDirectories:YES attributes:nil error:nil];
		for (PBGitTree* child in [self children])
			[child saveToFolder: newName];
	}
}

- (NSString*) tmpDirWithContents
{
	if (leaf)
		return nil;

	if (!localFileName)
		localFileName = [PBEasyFS tmpDirWithPrefix: path];

	for (PBGitTree* child in [self children]) {
		[child saveToFolder: localFileName];
	}
	
	return localFileName;
}

	

- (NSString*) tmpFileNameForContents
{
	if (!leaf)
		return [self tmpDirWithContents];
	
	if ([self isLocallyCached])
		return localFileName;
	
	if (!localFileName)
		localFileName = [[PBEasyFS tmpDirWithPrefix: sha] stringByAppendingPathComponent:path];
	
	NSFileHandle* handle = [repository handleForArguments:@[@"show", [self refSpec]]];
	NSData* data = [handle readDataToEndOfFile];
	[data writeToFile:localFileName atomically:YES];
	
	NSFileManager* fs = [NSFileManager defaultManager];
	localMtime = [fs attributesOfItemAtPath:localFileName error: nil][NSFileModificationDate];

	return localFileName;
}

- (NSArray*) children
{
	if (children != nil)
		return children;
	
	NSString* ref = [self refSpec];

	NSFileHandle* handle = [repository handleForArguments:@[@"show", ref]];
	[handle readLine];
	[handle readLine];
	
	NSMutableArray* c = [NSMutableArray array];
	
	NSString* p = [handle readLine];
	while (p.length > 0) {
		BOOL isLeaf = ([p characterAtIndex:p.length - 1] != '/');
		if (!isLeaf)
			p = [p substringToIndex:p.length -1];

		PBGitTree* child = [PBGitTree treeForTree:self andPath:p];
		child.leaf = isLeaf;
		[c addObject: child];
		
		p = [handle readLine];
	}
	children = c;
	return c;
}

- (NSString*) fullPath
{
	if (!parent)
		return @"";
	
	if ([parent.fullPath isEqualToString:@""])
		return self.path;
	
	return [parent.fullPath stringByAppendingPathComponent: self.path];
}

- (void) finalize
{
	if (localFileName)
		[[NSFileManager defaultManager] removeItemAtPath:localFileName error:nil];
	[super finalize];
}

- (BOOL)isEqualTo:(PBGitTree *)object
{
    return [self.sha isEqualToString:object.sha] && [self.fullPath isEqualToString:object.fullPath];
}
@end
