//
//  PBGitIndex.m
//  GitX
//
//  Created by Pieter de Bie on 9/12/09.
//  Copyright 2009 Pieter de Bie. All rights reserved.
//

#import "PBGitIndex.h"
#import "PBGitRepository.h"
#import "PBGitBinary.h"
#import "PBEasyPipe.h"
#import "PBGitDefaults.h"
#import "NSString_RegEx.h"
#import "PBChangedFile.h"

NSString *PBGitIndexIndexRefreshStatus = @"PBGitIndexIndexRefreshStatus";
NSString *PBGitIndexIndexRefreshFailed = @"PBGitIndexIndexRefreshFailed";
NSString *PBGitIndexFinishedIndexRefresh = @"PBGitIndexFinishedIndexRefresh";

NSString *PBGitIndexIndexUpdated = @"GBGitIndexIndexUpdated";

NSString *PBGitIndexCommitStatus = @"PBGitIndexCommitStatus";
NSString *PBGitIndexCommitFailed = @"PBGitIndexCommitFailed";
NSString *PBGitIndexCommitHookFailed = @"PBGitIndexCommitHookFailed";
NSString *PBGitIndexFinishedCommit = @"PBGitIndexFinishedCommit";

NSString *PBGitIndexAmendMessageAvailable = @"PBGitIndexAmendMessageAvailable";
NSString *PBGitIndexOperationFailed = @"PBGitIndexOperationFailed";

@interface PBGitIndex (IndexRefreshMethods)

- (NSArray *)linesFromNotification:(NSNotification *)notification;
- (NSMutableDictionary *)dictionaryForLines:(NSArray *)lines;
- (void)addFilesFromDictionary:(NSMutableDictionary *)dictionary staged:(BOOL)staged tracked:(BOOL)tracked;

- (void)indexStepComplete;

- (void)indexRefreshFinished:(NSNotification *)notification;
- (void)readOtherFiles:(NSNotification *)notification;
- (void)readUnstagedFiles:(NSNotification *)notification;
- (void)readStagedFiles:(NSNotification *)notification;

@end

@interface PBGitIndex ()

// Returns the tree to compare the index to, based
// on whether amend is set or not.
- (NSString *) parentTree;
- (void)postCommitUpdate:(NSString *)update;
- (void)postCommitFailure:(NSString *)reason;
- (void)postCommitHookFailure:(NSString *)reason;
- (void)postIndexChange;
- (void)postOperationFailed:(NSString *)description;
@end

@implementation PBGitIndex

@synthesize amend;

- (id)initWithRepository:(PBGitRepository *)theRepository workingDirectory:(NSURL *)theWorkingDirectory
{
	if (!(self = [super init]))
		return nil;

	NSAssert(theWorkingDirectory, @"PBGitIndex requires a working directory");
	NSAssert(theRepository, @"PBGitIndex requires a repository");

	repository = theRepository;
	workingDirectory = theWorkingDirectory;
	files = [NSMutableArray array];

	return self;
}

- (NSArray *)indexChanges
{
	return files;
}

- (void)setAmend:(BOOL)newAmend
{
	if (newAmend == amend)
		return;
	
	amend = newAmend;
	amendEnvironment = nil;

	[self refresh];

	if (!newAmend)
		return;

	// If we amend, we want to keep the author information for the previous commit
	// We do this by reading in the previous commit, and storing the information
	// in a dictionary. This dictionary will then later be read by [self commit:]
	NSString *message = [repository outputForCommand:@"cat-file commit HEAD"];
	NSArray *match = [message substringsMatchingRegularExpression:@"\nauthor ([^\n]*) <([^\n>]*)> ([0-9]+[^\n]*)\n" count:3 options:0 ranges:nil error:nil];
	if (match)
		amendEnvironment = @{@"GIT_AUTHOR_NAME": match[1],
							@"GIT_AUTHOR_EMAIL": match[2],
							@"GIT_AUTHOR_DATE": match[3]};

	// Find the commit message
	NSRange r = [message rangeOfString:@"\n\n"];
	if (r.location != NSNotFound) {
		NSString *commitMessage = [message substringFromIndex:r.location + 2];
		[[NSNotificationCenter defaultCenter] postNotificationName:PBGitIndexAmendMessageAvailable
															object: self
														  userInfo:@{@"message": commitMessage}];
	}
	
}

- (void)refresh
{
	// If we were already refreshing the index, we don't want
	// double notifications. As we can't stop the tasks anymore,
	// just cancel the notifications
	refreshStatus = 0;
	NSNotificationCenter *nc = [NSNotificationCenter defaultCenter]; 
	[nc removeObserver:self]; 

	// Ask Git to refresh the index
	NSFileHandle *updateHandle = [PBEasyPipe handleForCommand:[PBGitBinary path] 
													 withArgs:@[@"update-index", @"-q", @"--unmerged", @"--ignore-missing", @"--refresh"]
														inDir:[workingDirectory path]];

	[nc addObserver:self
		   selector:@selector(indexRefreshFinished:)
			   name:NSFileHandleReadToEndOfFileCompletionNotification
			 object:updateHandle];
	[updateHandle readToEndOfFileInBackgroundAndNotify];

}

- (NSString *) parentTree
{
	NSString *parent = amend ? @"HEAD^" : @"HEAD";
	
	if (![repository parseReference:parent])
		// We don't have a head ref. Return the empty tree.
		return @"4b825dc642cb6eb9a060e54bf8d69288fbee4904";

	return parent;
}


- (void)commitMergeWithMessage:(NSString *)commitMessage
{
	NSMutableString *commitSubject = [@"commit: " mutableCopy];
	NSRange newLine = [commitMessage rangeOfString:@"\n"];
	if (newLine.location == NSNotFound)
		[commitSubject appendString:commitMessage];
	else
		[commitSubject appendString:[commitMessage substringToIndex:newLine.location]];
	
	NSString *commitMessageFile;
	commitMessageFile = [repository.fileURL.path stringByAppendingPathComponent:@"COMMIT_EDITMSG"];
	
	[commitMessage writeToFile:commitMessageFile atomically:YES encoding:NSUTF8StringEncoding error:nil];

	NSArray *arguments = @[@"commit", @"-m", commitMessage];
        
    int ret = 1;
 	NSString *output = [repository outputInWorkdirForArguments:arguments retValue: &ret];
    
    NSMutableDictionary *userInfo = [NSMutableDictionary new];
    
	if (!ret)
    {
        userInfo[@"success"] = [NSNumber numberWithInt:YES];
        
        NSString *sha = [repository outputInWorkdirForArguments:@[@"log", @"-n1", @"--pretty=%H"] retValue: &ret];
        userInfo[@"sha"] = sha;

        userInfo[@"description"] = [NSString stringWithFormat:@"Successfully created merge commit %@", sha];
        
        repository.hasChanged = YES;
        [repository reloadRefs];
        
        amendEnvironment = nil;
        if (amend)
            self.amend = NO;
        else
            [self refresh];
    }
	else
    {
        userInfo[@"success"] = [NSNumber numberWithInt:NO];
        userInfo[@"description"] = [NSString stringWithFormat:@"Commiting the merge occurs an error - %@",output];
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:PBGitIndexFinishedCommit
                                                        object:self
                                                      userInfo:userInfo];
}


// TODO: make Asynchronous
- (void)commitWithMessage:(NSString *)commitMessage andVerify:(BOOL) doVerify
{
	NSMutableString *commitSubject = [@"commit: " mutableCopy];
	NSRange newLine = [commitMessage rangeOfString:@"\n"];
	if (newLine.location == NSNotFound)
		[commitSubject appendString:commitMessage];
	else
		[commitSubject appendString:[commitMessage substringToIndex:newLine.location]];
	
	NSString *commitMessageFile;
	commitMessageFile = [repository.fileURL.path stringByAppendingPathComponent:@"COMMIT_EDITMSG"];
	
	[commitMessage writeToFile:commitMessageFile atomically:YES encoding:NSUTF8StringEncoding error:nil];

	
	[self postCommitUpdate:@"Creating tree"];
	NSString *tree = [repository outputForCommand:@"write-tree"];
	if ([tree length] != 40)
		return [self postCommitFailure:@"Creating tree failed"];
	
	
	NSMutableArray *arguments = [NSMutableArray arrayWithObjects:@"commit-tree", tree, nil];
	NSString *parent = amend ? @"HEAD^" : @"HEAD";
	if ([repository parseReference:parent]) {
		[arguments addObject:@"-p"];
		[arguments addObject:parent];
	}

	[self postCommitUpdate:@"Creating commit"];
	int ret = 1;
	
    if (doVerify) {
        [self postCommitUpdate:@"Running hooks"];
        NSString *hookFailureMessage = nil;
        NSString *hookOutput = nil;
        if (![repository executeHook:@"pre-commit" output:&hookOutput]) {
            hookFailureMessage = [NSString stringWithFormat:@"Pre-commit hook failed%@%@",
                                  [hookOutput length] > 0 ? @":\n" : @"",
                                  hookOutput];
        }

        if (![repository executeHook:@"commit-msg" withArgs:@[commitMessageFile] output:&hookOutput]) {
            hookFailureMessage = [NSString stringWithFormat:@"Commit-msg hook failed%@%@",
                                  [hookOutput length] > 0 ? @":\n" : @"",
                                  hookOutput];
        }

        if (hookFailureMessage != nil) {
            return [self postCommitHookFailure:hookFailureMessage];
        }
    }
	
	commitMessage = [NSString stringWithContentsOfFile:commitMessageFile encoding:NSUTF8StringEncoding error:nil];
	
	NSString *commit = [repository outputForArguments:arguments
										  inputString:commitMessage
							   byExtendingEnvironment:amendEnvironment
											 retValue: &ret];
	
	if (ret || [commit length] != 40)
		return [self postCommitFailure:@"Could not create a commit object"];
	
	[self postCommitUpdate:@"Updating HEAD"];
	[repository outputForArguments:@[@"update-ref", @"-m", commitSubject, @"HEAD", commit]
						  retValue: &ret];
	if (ret)
		return [self postCommitFailure:@"Could not update HEAD"];
	
	[self postCommitUpdate:@"Running post-commit hook"];
	
	BOOL success = [repository executeHook:@"post-commit" output:nil];
	NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObject:@(success) forKey:@"success"];
	NSString *description;  
	if (success)
		description = [NSString stringWithFormat:@"Successfully created commit %@", commit];
	else
		description = [NSString stringWithFormat:@"Post-commit hook failed, but successfully created commit %@", commit];
	
	userInfo[@"description"] = description;
	userInfo[@"sha"] = commit;

	[[NSNotificationCenter defaultCenter] postNotificationName:PBGitIndexFinishedCommit
														object:self
													  userInfo:userInfo];
	if (!success)
		return;

	repository.hasChanged = YES;
    [repository reloadRefs];

	amendEnvironment = nil;
	if (amend)
		self.amend = NO;
	else
		[self refresh];
	
}

- (void)postCommitUpdate:(NSString *)update
{
	[[NSNotificationCenter defaultCenter] postNotificationName:PBGitIndexCommitStatus
													object:self
													  userInfo:@{@"description": update}];
}

- (void)postCommitFailure:(NSString *)reason
{
	[[NSNotificationCenter defaultCenter] postNotificationName:PBGitIndexCommitFailed
														object:self
													  userInfo:@{@"description": reason}];
}

- (void)postCommitHookFailure:(NSString *)reason
{
	[[NSNotificationCenter defaultCenter] postNotificationName:PBGitIndexCommitHookFailed
														object:self
													  userInfo:@{@"description": reason}];
}

- (void)postOperationFailed:(NSString *)description
{
	[[NSNotificationCenter defaultCenter] postNotificationName:PBGitIndexOperationFailed
														object:self
													  userInfo:@{@"description": description}];	
}

- (BOOL)stageFiles:(NSArray *)stageFiles
{
	// Do staging files by chunks of 1000 files each, to prevent program freeze (because NSPipe has limited capacity)
	
	int filesCount = [stageFiles count];
	
	// Prepare first iteration
	int loopFrom = 0;
	int loopTo = 1000;
	if (loopTo > filesCount)
		loopTo = filesCount;
	int loopCount = 0;
	int i = 0;
	
	// Staging
	while (loopCount < filesCount) {
		// Input string for update-index
		// This will be a list of filenames that
		// should be updated. It's similar to
		// "git add -- <files>
		NSMutableString *input = [NSMutableString string];

		for (i = loopFrom; i < loopTo; i++) {
			loopCount++;
			
			PBChangedFile *file = stageFiles[i];
			
			[input appendFormat:@"%@", file.path];
			[input appendString:@"\n"];
		}
		
			
		int ret = 1;
		[repository outputForArguments:@[@"update-index", @"--add", @"--remove", @"--stdin"]
						   inputString:input
							  retValue:&ret];

		if (ret) {
			[self postOperationFailed:[NSString stringWithFormat:@"Error in staging files. Return value: %i", ret]];
			return NO;
		}

		for (i = loopFrom; i < loopTo; i++) {
			PBChangedFile *file = stageFiles[i];
			
			file.hasUnstagedChanges = NO;
			file.hasStagedChanges = YES;
		}
		
		// Prepare next iteration
		loopFrom = loopCount;
		loopTo = loopFrom + 1000;
		if (loopTo > filesCount)
			loopTo = filesCount;
	}

	[self postIndexChange];
	return YES;
}

// TODO: Refactor with above. What's a better name for this?
- (BOOL)unstageFiles:(NSArray *)unstageFiles
{
	// Do unstaging files by chunks of 1000 files each, to prevent program freeze (because NSPipe has limited capacity)
	
	int filesCount = [unstageFiles count];
	
	// Prepare first iteration
	int loopFrom = 0;
	int loopTo = 1000;
	if (loopTo > filesCount)
		loopTo = filesCount;
	int loopCount = 0;
	int i = 0;
	
	// Unstaging
	while (loopCount < filesCount) {
		NSMutableString *input = [NSMutableString string];
		
		for (i = loopFrom; i < loopTo; i++) {
			loopCount++;
			
			PBChangedFile *file = unstageFiles[i];
			
			[input appendString:[file indexInfo]];
			[input appendString:@"\n"];
		}
		
		int ret = 1;
		[repository outputForArguments:@[@"update-index", @"--index-info"]
						   inputString:input
							  retValue:&ret];
		
		if (ret)
		{
			[self postOperationFailed:[NSString stringWithFormat:@"Error in unstaging files. Return value: %i", ret]];
			return NO;
		}
		
		for (i = loopFrom; i < loopTo; i++) {
			PBChangedFile *file = unstageFiles[i];
			
			file.hasUnstagedChanges = YES;
			file.hasStagedChanges = NO;
		}
		
		// Prepare next iteration
		loopFrom = loopCount;
		loopTo = loopFrom + 1000;
		if (loopTo > filesCount)
			loopTo = filesCount;
	}

	[self postIndexChange];
	return YES;
}

- (void)discardChangesForFiles:(NSArray *)discardFiles
{
	NSArray *paths = [discardFiles valueForKey:@"path"];
	NSString *input = [paths componentsJoinedByString:@"\n"];

	NSArray *arguments = @[@"checkout-index", @"--index", @"--quiet", @"--force", @"--stdin"];

	int ret = 1;
	[PBEasyPipe outputForCommand:[PBGitBinary path]	withArgs:arguments inDir:[workingDirectory path] inputString:input retValue:&ret];

	if (ret) {
		[self postOperationFailed:[NSString stringWithFormat:@"Discarding changes failed with return value %i", ret]];
		return;
	}

	for (PBChangedFile *file in discardFiles)
		if (file.status != NEW)
			file.hasUnstagedChanges = NO;

	[self postIndexChange];
}

- (BOOL)applyPatch:(NSString *)hunk stage:(BOOL)stage reverse:(BOOL)reverse;
{
	NSMutableArray *array = [NSMutableArray arrayWithObjects:@"apply", @"--unidiff-zero", nil];
	if (stage)
		[array addObject:@"--cached"];
	if (reverse)
		[array addObject:@"--reverse"];

	int ret = 1;
	NSString *error = [repository outputForArguments:array
										 inputString:hunk
											retValue:&ret];

	if (ret) {
		[self postOperationFailed:[NSString stringWithFormat:@"Applying patch failed with return value %i. Error: %@", ret, error]];
		return NO;
	}

	// TODO: Try to be smarter about what to refresh
	[self refresh];
	return YES;
}


- (NSString *)diffForFile:(PBChangedFile *)file staged:(BOOL)staged contextLines:(NSUInteger)context
{
	NSString *parameter = [NSString stringWithFormat:@"-U%lu", context];
	if (staged) {
		NSString *indexPath = [@":0:" stringByAppendingString:file.path];

		if (file.status == NEW)
			return [repository outputForArguments:@[@"show", indexPath]];

        NSMutableArray *arguments = [NSMutableArray arrayWithObjects:@"diff-index", parameter, @"--cached", [self parentTree], @"--", file.path, nil];
        if (![PBGitDefaults showWhitespaceDifferences])
            [arguments insertObject:@"-w" atIndex:2];
		return [repository outputInWorkdirForArguments:arguments];
	}

	// unstaged
	if (file.status == NEW) {
		NSStringEncoding encoding;
		NSError *error = nil;
		NSString *path = [[repository workingDirectory] stringByAppendingPathComponent:file.path];
        
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSDictionary *fileAttributes = [fileManager attributesOfItemAtPath:path error:&error];

        if (error)
			return nil;
        
        NSInteger sizeOnDisk = [fileAttributes[NSFileSize] intValue];
        
        if (sizeOnDisk > 10000000) {
            // Don't load files larger than 10MB to prevent the app from freezing.
            return nil;
        }
		else {
            NSString *contents = [NSString stringWithContentsOfFile:path
                                                       usedEncoding:&encoding
                                                              error:&error];
            if (error)
                return nil;
            return contents;   
        }
	}

    NSMutableArray *arguments = [NSMutableArray arrayWithObjects:@"diff-files", parameter, @"--", file.path, nil];
    if (![PBGitDefaults showWhitespaceDifferences])
        [arguments insertObject:@"-w" atIndex:2];
	return [repository outputInWorkdirForArguments:arguments];
}

- (void)postIndexChange
{
	[[NSNotificationCenter defaultCenter] postNotificationName:PBGitIndexIndexUpdated
														object:self];
}

# pragma mark WebKit Accessibility

+ (BOOL)isSelectorExcludedFromWebScript:(SEL)aSelector
{
	return NO;
}

@end

@implementation PBGitIndex (IndexRefreshMethods)

- (void)indexRefreshFinished:(NSNotification *)notification
{
	if ([(NSNumber *)((NSDictionary *)[notification userInfo])[@"NSFileHandleError"] intValue])
	{
		[[NSNotificationCenter defaultCenter] postNotificationName:PBGitIndexIndexRefreshFailed
															object:self
														  userInfo:@{@"description": @"update-index failed"}];
		return;
	}

	[[NSNotificationCenter defaultCenter] postNotificationName:PBGitIndexIndexRefreshStatus
														object:self
													  userInfo:@{@"description": @"update-index success"}];

	// Now that the index is refreshed, we need to read the information from the index
	NSNotificationCenter *nc = [NSNotificationCenter defaultCenter]; 

	// Other files (not tracked, not ignored)
	refreshStatus++;
	NSFileHandle *handle = [PBEasyPipe handleForCommand:[PBGitBinary path] 
											   withArgs:@[@"ls-files", @"--others", @"--exclude-standard"]
												  inDir:[workingDirectory path]];
	[nc addObserver:self selector:@selector(readOtherFiles:) name:NSFileHandleReadToEndOfFileCompletionNotification object:handle]; 
	[handle readToEndOfFileInBackgroundAndNotify];

	// Unstaged files
	refreshStatus++;
	handle = [PBEasyPipe handleForCommand:[PBGitBinary path] 
											   withArgs:@[@"diff-files"]
												  inDir:[workingDirectory path]];
	[nc addObserver:self selector:@selector(readUnstagedFiles:) name:NSFileHandleReadToEndOfFileCompletionNotification object:handle]; 
	[handle readToEndOfFileInBackgroundAndNotify];

	// Staged files
	refreshStatus++;
	handle = [PBEasyPipe handleForCommand:[PBGitBinary path] 
								 withArgs:@[@"diff-index", @"--cached", [self parentTree]]
									inDir:[workingDirectory path]];
	[nc addObserver:self selector:@selector(readStagedFiles:) name:NSFileHandleReadToEndOfFileCompletionNotification object:handle]; 
	[handle readToEndOfFileInBackgroundAndNotify];
}

- (void)readOtherFiles:(NSNotification *)notification
{
	NSArray *lines = [self linesFromNotification:notification];
	NSMutableDictionary *dictionary = [[NSMutableDictionary alloc] initWithCapacity:[lines count]];
	// Other files are untracked, so we don't have any real index information. Instead, we can just fake it.
	// The line below is not used at all, as for these files the commitBlob isn't set
	NSArray *fileStatus = @[@":000000", @"100644", @"0000000000000000000000000000000000000000", @"0000000000000000000000000000000000000000", @"A"];
	for (NSString *path in lines) {
		if ([path length] == 0)
			continue;
		dictionary[path] = fileStatus;
	}

	[self addFilesFromDictionary:dictionary staged:NO tracked:NO];
	[self indexStepComplete];	
}

- (void) readStagedFiles:(NSNotification *)notification
{
	NSArray *lines = [self linesFromNotification:notification];
	NSMutableDictionary *dic = [self dictionaryForLines:lines];
	[self addFilesFromDictionary:dic staged:YES tracked:YES];
	[self indexStepComplete];
}

- (void) readUnstagedFiles:(NSNotification *)notification
{
	NSArray *lines = [self linesFromNotification:notification];
	NSMutableDictionary *dic = [self dictionaryForLines:lines];
	[self addFilesFromDictionary:dic staged:NO tracked:YES];
	[self indexStepComplete];
}

- (void) addFilesFromDictionary:(NSMutableDictionary *)dictionary staged:(BOOL)staged tracked:(BOOL)tracked
{
	// Iterate over all existing files
	for (PBChangedFile *file in files) {
		NSArray *fileStatus = dictionary[file.path];
		// Object found, this is still a cached / uncached thing
		if (fileStatus) {
			if (tracked) {
				NSString *mode = [fileStatus[0] substringFromIndex:1];
				NSString *sha = fileStatus[2];
				file.commitBlobSHA = sha;
				file.commitBlobMode = mode;
				
				if (staged)
					file.hasStagedChanges = YES;
				else
					file.hasUnstagedChanges = YES;
				if ([fileStatus[4] isEqualToString:@"D"])
					file.status = DELETED;
			} else {
				// Untracked file, set status to NEW, only unstaged changes
				file.hasStagedChanges = NO;
				file.hasUnstagedChanges = YES;
				file.status = NEW;
			}

			// We handled this file, remove it from the dictionary
			[dictionary removeObjectForKey:file.path];
		} else {
			// Object not found in the dictionary, so let's reset its appropriate
			// change (stage or untracked) if necessary.

			// Staged dictionary, so file does not have staged changes
			if (staged)
				file.hasStagedChanges = NO;
			// Tracked file does not have unstaged changes, file is not new,
			// so we can set it to No. (If it would be new, it would not
			// be in this dictionary, but in the "other dictionary").
			else if (tracked && file.status != NEW)
				file.hasUnstagedChanges = NO;
			// Unstaged, untracked dictionary ("Other" files), and file
			// is indicated as new (which would be untracked), so let's
			// remove it
			else if (!tracked && file.status == NEW)
				file.hasUnstagedChanges = NO;
		}
	}

	// Do new files only if necessary
	if (![[dictionary allKeys] count])
		return;

	// All entries left in the dictionary haven't been accounted for
	// above, so we need to add them to the "files" array
	[self willChangeValueForKey:@"indexChanges"];
	for (NSString *path in [dictionary allKeys]) {
		NSArray *fileStatus = dictionary[path];

		PBChangedFile *file = [[PBChangedFile alloc] initWithPath:path];
		if ([fileStatus[4] isEqualToString:@"D"])
			file.status = DELETED;
		else if([fileStatus[0] isEqualToString:@":000000"])
			file.status = NEW;
		else
			file.status = MODIFIED;

		if (tracked) {
			file.commitBlobMode = [fileStatus[0] substringFromIndex:1];
			file.commitBlobSHA = fileStatus[2];
		}

		file.hasStagedChanges = staged;
		file.hasUnstagedChanges = !staged;

		[files addObject:file];
	}
	[self didChangeValueForKey:@"indexChanges"];
}

# pragma mark Utility methods
- (NSArray *)linesFromNotification:(NSNotification *)notification
{
	NSData *data = [[notification userInfo] valueForKey:NSFileHandleNotificationDataItem];
	if (!data)
		return @[];

	NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	if (!string)
		return @[];

	if ([string length] == 0)
		return @[];

    string=[string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	return [string componentsSeparatedByString:@"\n"];
}

- (NSMutableDictionary *)dictionaryForLines:(NSArray *)lines
{
	NSMutableDictionary *dictionary = [NSMutableDictionary dictionaryWithCapacity:[lines count]];

	NSEnumerator *enumerator = [lines objectEnumerator];
	NSString *line;
	while ((line = [enumerator nextObject])) {
        NSArray *lineComp=[line componentsSeparatedByString:@"\t"];
        NSArray *fileStatus=[lineComp[0] componentsSeparatedByString:@" "];
		NSString *fileName = lineComp[1];
		dictionary[fileName] = fileStatus;
	}

	return dictionary;
}

// This method is called for each of the three processes from above.
// If all three are finished (self.busy == 0), then we can delete
// all files previously marked as deletable
- (void)indexStepComplete
{
	// if we're still busy, do nothing :)
	if (--refreshStatus) {
		[self postIndexChange];
		return;
	}

	// At this point, all index operations have finished.
	// We need to find all files that don't have either
	// staged or unstaged files, and delete them

	NSMutableArray *deleteFiles = [NSMutableArray array];
	for (PBChangedFile *file in files) {
		if (!file.hasStagedChanges && !file.hasUnstagedChanges)
			[deleteFiles addObject:file];
	}
	
	if ([deleteFiles count]) {
		[self willChangeValueForKey:@"indexChanges"];
		for (PBChangedFile *file in deleteFiles)
			[files removeObject:file];
		[self didChangeValueForKey:@"indexChanges"];
	}

	[[NSNotificationCenter defaultCenter] postNotificationName:PBGitIndexFinishedIndexRefresh
														object:self];
	[self postIndexChange];

}

@end
