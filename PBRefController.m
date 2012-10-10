//
//  PBLabelController.m
//  GitX
//
//  Created by Pieter de Bie on 21-10-08.
//  Copyright 2008 Pieter de Bie. All rights reserved.
//

#import "PBRefController.h"
#import "PBGitRevisionCell.h"
#import "PBRefMenuItem.h"
#import "PBCreateBranchSheet.h"
#import "PBCreateTagSheet.h"
#import "PBGitDefaults.h"
#import "PBDiffWindowController.h"
#import "PBGitResetController.h"
#import "PBRenameSheet.h"
#import "PBArgumentPickerController.h"
#import "PBChangeRemoteUrlSheet.h"

#define kDialogAcceptDroppedRef @"Accept Dropped Ref"
#define kDialogConfirmPush @"Confirm Push"
#define kDialogDeleteRef @"Delete Ref"
#define kDialogRenameRef @"Rename Ref"
#define kDialogDeleteRemoteBranch @"Delete Remote Branch"
#define kDialogDeleteRemoteTag @"Delete Remote Tag"

@implementation PBRefController

@synthesize historyController;

-(void)dealloc
{
    actDropInfo = Nil;
    actRef = Nil;
}

- (void)awakeFromNib
{
	[commitList registerForDraggedTypes:@[@"PBGitRef"]];
}


#pragma mark Fetch

- (void) fetchRemote:(PBRefMenuItem *)sender
{
	id <PBGitRefish> refish = [sender refish];
	if ([refish refishType] == kGitXCommitType)
		return;

	[historyController.repository beginFetchFromRemoteForRef:refish];
}


#pragma mark Pull

- (void) pullRemote:(PBRefMenuItem *)sender
{
	id <PBGitRefish> refish = [sender refish];
	[historyController.repository beginPullFromRemote:nil forRef:refish];
}

#pragma mark Github
- (void) githubRemote:(PBRefMenuItem *)sender
{
    
    PBGitCommit * commit = nil;
    if([[sender refish] refishType] == kGitXCommitType)
        commit = (PBGitCommit *)[sender refish];
    else
        commit = [historyController.repository commitForRef:[sender refish]];

    
	PBGitRef* refish = (PBGitRef *)[sender refish];
    
//    [historyContrioller.repository beginPullFromRemote:nil forRef:refish];
    PBGitRef * remoteRef;
    remoteRef = refish;
    // a nil remoteRef means lookup the ref's default remote
	if ((!remoteRef) || (![remoteRef isRemote])) {
		NSError *error = nil;
		remoteRef = [historyController.repository remoteRefForBranch:refish error:&error];
		if (!remoteRef) {
			if (error)
				[historyController.repository.windowController showErrorSheet:error];
			return;
		}
	}
	NSString *remoteName = [remoteRef remoteName];
    
}


#pragma mark Push

- (void)showConfirmPushRefSheet:(PBGitRef *)ref remote:(PBGitRef *)remoteRef
{
	if ((!ref && !remoteRef)
		|| (ref && ![ref isTag] && ![ref isBranch] && ![ref isRemoteBranch])
		|| (remoteRef && !([remoteRef refishType] == kGitXRemoteType)))
		return;

	if ([PBGitDefaults isDialogWarningSuppressedForDialog:kDialogConfirmPush]) {
		[historyController.repository beginPushRef:ref toRemote:remoteRef];
		return;
	}

	NSString *description = nil;
	if (ref && remoteRef)
		description = [NSString stringWithFormat:@"Push %@ '%@' to remote %@", [ref refishType], [ref shortName], [remoteRef remoteName]];
	else if (ref)
		description = [NSString stringWithFormat:@"Push %@ '%@' to default remote", [ref refishType], [ref shortName]];
	else
		description = [NSString stringWithFormat:@"Push updates to remote %@", [remoteRef remoteName]];

    NSString * sdesc = [NSString stringWithFormat:@"p%@", [description substringFromIndex:1]]; 
	NSAlert *alert = [NSAlert alertWithMessageText:description
									 defaultButton:@"Push"
								   alternateButton:@"Cancel"
									   otherButton:nil
						 informativeTextWithFormat:@"Are you sure you want to %@?", sdesc];
    [alert setShowsSuppressionButton:YES];

	NSMutableDictionary *info = [NSMutableDictionary dictionary];
	if (ref)
		info[kGitXBranchType] = ref;
	if (remoteRef)
		info[kGitXRemoteType] = remoteRef;

    NSInteger returnCode=[alert runModal];
    
	if ([[alert suppressionButton] state] == NSOnState)
        [PBGitDefaults suppressDialogWarningForDialog:kDialogConfirmPush];

	if (returnCode == NSAlertDefaultReturn) {
		PBGitRef *ref = info[kGitXBranchType];
		PBGitRef *remoteRef = info[kGitXRemoteType];

		[historyController.repository beginPushRef:ref toRemote:remoteRef];
	}
}

- (void) pushUpdatesToRemote:(PBRefMenuItem *)sender
{
	PBGitRef *remoteRef = [(PBGitRef *)[sender refish] remoteRef];

	[self showConfirmPushRefSheet:nil remote:remoteRef];
}

- (void) pushDefaultRemoteForRef:(PBRefMenuItem *)sender
{
	PBGitRef *ref = (PBGitRef *)[sender refish];

	[self showConfirmPushRefSheet:ref remote:nil];
}

- (void) pushToRemote:(PBRefMenuItem *)sender
{
	PBGitRef *ref = (PBGitRef *)[sender refish];
	NSString *remoteName = [sender representedObject];
	PBGitRef *remoteRef = [PBGitRef refFromString:[kGitXRemoteRefPrefix stringByAppendingString:remoteName]];

	[self showConfirmPushRefSheet:ref remote:remoteRef];
}


#pragma mark Merge

- (void) merge:(PBRefMenuItem *)sender
{
	id <PBGitRefish> refish = [sender refish];
	[historyController.repository mergeWithRefish:refish];
}


#pragma mark Checkout

- (void) checkout:(PBRefMenuItem *)sender
{
	id <PBGitRefish> refish = [sender refish];
	[historyController.repository checkoutRefish:refish];
}

#pragma mark Reset

- (void) reset:(PBRefMenuItem *)sender
{
	id <PBGitRefish> refish = [sender refish];
	[historyController.repository.resetController resetToRefish: refish type: PBResetTypeMixed];
}

#pragma mark Cherry Pick

- (void) cherryPick:(PBRefMenuItem *)sender
{
	id <PBGitRefish> refish = [sender refish];
	[historyController.repository cherryPickRefish:refish];
}


#pragma mark Rebase

- (void) rebaseHeadBranch:(PBRefMenuItem *)sender
{
	id <PBGitRefish> refish = [sender refish];

	[historyController.repository rebaseBranch:nil onRefish:refish];
}


#pragma mark Create Branch

- (void) createBranch:(PBRefMenuItem *)sender
{
	id <PBGitRefish> refish = [sender refish];
	[PBCreateBranchSheet beginCreateBranchSheetAtRefish:refish inRepository:historyController.repository];
}


#pragma mark Copy info

- (void) copySHA:(PBRefMenuItem *)sender
{
	PBGitCommit *commit = nil;
	if ([[sender refish] refishType] == kGitXCommitType)
		commit = (PBGitCommit *)[sender refish];
	else
		commit = [historyController.repository commitForRef:[sender refish]];

	NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
	[pasteboard declareTypes:@[NSStringPboardType] owner:nil];
	[pasteboard setString:[commit realSha] forType:NSStringPboardType];
}

#pragma mark Open in Github
- (void) openInGithub:(PBRefMenuItem *)sender
{
    PBGitCommit * commit = nil;
    if([[sender refish] refishType] == kGitXCommitType)
        commit = (PBGitCommit *)[sender refish];
    else
        commit = [historyController.repository commitForRef:[sender refish]];
    /*
    [[commit repository] outputInWorkdirForArguments: @[@"open",
     [[[[[commit repository] remoteUrl: @"origin"]
        stringByReplacingOccurancesOfString: ".git" withString: ""]
         stringByAppendingString: @"commit/"]
           stringByAppendingString: [commit realSha]]]];
     */
}

- (void) copyPatch:(PBRefMenuItem *)sender
{
	PBGitCommit *commit = nil;
	if ([[sender refish] refishType] == kGitXCommitType)
		commit = (PBGitCommit *)[sender refish];
	else
		commit = [historyController.repository commitForRef:[sender refish]];

	NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
	[pasteboard declareTypes:@[NSStringPboardType] owner:nil];
	[pasteboard setString:[commit patch] forType:NSStringPboardType];
}


#pragma mark Diff

- (void) diffWithHEAD:(PBRefMenuItem *)sender
{
	PBGitCommit *commit = nil;
	if ([[sender refish] refishType] == kGitXCommitType)
		commit = (PBGitCommit *)[sender refish];
	else
		commit = [historyController.repository commitForRef:[sender refish]];

	[PBDiffWindowController showDiffWindowWithFiles:nil fromCommit:commit diffCommit:nil];
}

#pragma mark Tags

- (void) createTag:(PBRefMenuItem *)sender
{
	id <PBGitRefish> refish = [sender refish];
	[PBCreateTagSheet beginCreateTagSheetAtRefish:refish inRepository:historyController.repository];
}

- (void) showTagInfoSheet:(PBRefMenuItem *)sender
{	
	if ([[sender refish] refishType] != kGitXTagType)
		return;

    PBGitRef *ref = (PBGitRef*)[sender refish]; 
    NSMutableString *info = [NSMutableString new];
    
    NSArray *remotes = [historyController.repository remotes];
    if (remotes)
    {
        for (int i=0; i<[remotes count]; i++)
        {
            if ([historyController.repository isRemoteConnected:remotes[i]])
            {
                [info appendFormat:@"On remote %@:\n%@\n\n",remotes[i],[historyController.repository tagExistsOnRemote:ref remoteName:remotes[i]]?@"Yes":@"No"];
            }
            else
            {
                [info appendFormat:@"Remote %@ is not connected!\nCan't check, if tag %@ exists.\n\n",remotes[i],[ref tagName]];
            }
        }
    }
    
	int retValue = 1;
	NSArray *args = @[@"tag", @"-n50", @"-l", [ref tagName]];
	NSString *output = [historyController.repository outputInWorkdirForArguments:args retValue:&retValue];    
	if (!retValue) 
    {
        [info appendFormat:@"Annotation or Commitmessage:\n%@",output];
	}
    else
    {
        [info appendFormat:@"Error:\ngit tag -n50 -l %@\n\n%@",[ref tagName],output];
	}

    NSString *message = [NSString stringWithFormat:@"Info for tag: %@", [ref tagName]];
    [historyController.repository.windowController showMessageSheet:message infoText:info];
}


#pragma mark Remove a branch, remote or tag

- (void)showDeleteRefSheet:(PBRefMenuItem *)sender
{
	if ([[sender refish] refishType] == kGitXCommitType)
		return;

	PBGitRef *ref = (PBGitRef *)[sender refish];

	if ([PBGitDefaults isDialogWarningSuppressedForDialog:kDialogDeleteRef]) {
		[historyController.repository deleteRef:ref];
		return;
	}

	NSString *ref_desc = [NSString stringWithFormat:@"%@ '%@'", [ref refishType], [ref shortName]];

	NSAlert *alert = [NSAlert alertWithMessageText:[NSString stringWithFormat:@"Delete %@?", ref_desc]
									 defaultButton:@"Delete"
								   alternateButton:@"Cancel"
									   otherButton:nil
						 informativeTextWithFormat:@"Are you sure you want to remove the %@?", ref_desc];
    [alert setShowsSuppressionButton:YES];
	
	[alert beginSheetModalForWindow:[historyController.repository.windowController window]
					  modalDelegate:self
					 didEndSelector:@selector(deleteRefSheetDidEnd:returnCode:contextInfo:)
						contextInfo:Nil];
    actRef = ref;
}


- (void)showRenameSheet:(PBRefMenuItem *)sender
{
	if ([[sender refish] refishType] == kGitXCommitType)
		return;
    
	PBGitRef *ref = (PBGitRef *)[sender refish];

    [PBRenameSheet showRenameSheetAtRef:ref inRepository:historyController.repository];
}


- (void) copyRefName:(PBRefMenuItem *)sender
{
	PBGitRef *ref = (PBGitRef *)[sender refish];
	
	NSPasteboard *pasteBoard =[NSPasteboard generalPasteboard];
	[pasteBoard declareTypes:@[NSStringPboardType] owner:self];
	[pasteBoard setString:[ref shortName] forType: NSStringPboardType];
}


- (void)showChangeRemoteUrlSheet:(PBRefMenuItem *)sender
{
    [PBChangeRemoteUrlSheet showChangeRemoteUrlSheetAtRefish:(PBGitRef *)[sender refish] inRepository:historyController.repository];
}

- (void)deleteRefSheetDidEnd:(NSAlert *)sheet returnCode:(int)returnCode contextInfo:(void  *)contextInfo
{
    [[sheet window] orderOut:nil];

	if ([[sheet suppressionButton] state] == NSOnState)
        [PBGitDefaults suppressDialogWarningForDialog:kDialogDeleteRef];

	if (returnCode == NSAlertDefaultReturn) {
		[historyController.repository deleteRef:actRef];
	}
}


#pragma mark Contextual menus

- (NSArray *) menuItemsForRef:(PBGitRef *)ref
{
	return [PBRefMenuItem defaultMenuItemsForRef:ref inRepository:historyController.repository target:self];
}

- (NSArray *) menuItemsForCommit:(PBGitCommit *)commit
{
	return [PBRefMenuItem defaultMenuItemsForCommit:commit target:self];
}

- (NSArray *)menuItemsForRow:(NSInteger)rowIndex
{
	NSArray *commits = [commitController arrangedObjects];
	if ([commits count] <= rowIndex)
		return nil;

	return [self menuItemsForCommit:commits[rowIndex]];
}


# pragma mark Tableview delegate methods

- (BOOL)tableView:(NSTableView *)tv writeRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard*)pboard
{
	NSPoint location = [tv convertPointFromBase:[(PBCommitList *)tv mouseDownPoint]];
	int row = [tv rowAtPoint:location];
	int column = [tv columnAtPoint:location];
	int subjectColumn = [tv columnWithIdentifier:@"SubjectColumn"];
	if (column != subjectColumn)
		return NO;
	
	PBGitRevisionCell *cell = (PBGitRevisionCell *)[tv preparedCellAtColumn:column row:row];
	NSRect cellFrame = [tv frameOfCellAtColumn:column row:row];
	
	int index = [cell indexAtX:(location.x - cellFrame.origin.x)];
	
	if (index == -1)
		return NO;

	PBGitRef *ref = [[cell objectValue] refs][index];
	if ([ref isTag] || [ref isRemoteBranch])
		return NO;

	if ([[[historyController.repository headRef] ref] isEqualToRef:ref])
		return NO;
	
	NSData *data = [NSKeyedArchiver archivedDataWithRootObject:@[@(row), @(index)]];
	[pboard declareTypes:@[@"PBGitRef"] owner:self];
	[pboard setData:data forType:@"PBGitRef"];
	
	return YES;
}

- (NSDragOperation)tableView:(NSTableView*)tv
				validateDrop:(id <NSDraggingInfo>)info
				 proposedRow:(NSInteger)row
	   proposedDropOperation:(NSTableViewDropOperation)operation
{
	if (operation == NSTableViewDropAbove)
		return NSDragOperationNone;
	
	NSPasteboard *pboard = [info draggingPasteboard];
	if ([pboard dataForType:@"PBGitRef"])
		return NSDragOperationMove;
	
	return NSDragOperationNone;
}

- (void) dropRef:(NSDictionary*)dropInfo
{
	PBGitRef *ref = dropInfo[@"dragRef"];
	PBGitCommit *oldCommit = dropInfo[@"oldCommit"];
	PBGitCommit *dropCommit = dropInfo[@"dropCommit"];
	if (!ref || ! oldCommit || !dropCommit)
		return;

	int retValue = 1;
	[historyController.repository outputForArguments:@[@"update-ref", @"-mUpdate from GitX", [ref ref], [dropCommit realSha]] retValue:&retValue];
	if (retValue)
		return;

	[dropCommit addRef:ref];
	[oldCommit removeRef:ref];
	[historyController.commitList reloadData];
}

- (BOOL)tableView:(NSTableView *)aTableView
	   acceptDrop:(id <NSDraggingInfo>)info
			  row:(NSInteger)row
	dropOperation:(NSTableViewDropOperation)operation
{
	if (operation != NSTableViewDropOn)
		return NO;
	
	NSPasteboard *pboard = [info draggingPasteboard];
	NSData *data = [pboard dataForType:@"PBGitRef"];
	if (!data)
		return NO;
	
	NSArray *numbers = [NSKeyedUnarchiver unarchiveObjectWithData:data];
	int oldRow = [numbers[0] intValue];
	if (oldRow == row)
		return NO;

	int oldRefIndex = [numbers[1] intValue];
	PBGitCommit *oldCommit = [commitController arrangedObjects][oldRow];
	PBGitRef *ref = [oldCommit refs][oldRefIndex];

	PBGitCommit *dropCommit = [commitController arrangedObjects][row];

	NSDictionary *dropInfo = @{@"dragRef": ref,
                              @"oldCommit": oldCommit,
                              @"dropCommit": dropCommit};

	if ([PBGitDefaults isDialogWarningSuppressedForDialog:kDialogAcceptDroppedRef]) {
		[self dropRef:dropInfo];
		return YES;
	}

	NSString *subject = [dropCommit subject];
	if ([subject length] > 99)
		subject = [[subject substringToIndex:99] stringByAppendingString:@"…"];

	NSAlert *alert = [NSAlert alertWithMessageText:[NSString stringWithFormat:@"Move %@: %@", [ref refishType], [ref shortName]]
									 defaultButton:@"Move"
								   alternateButton:@"Cancel"
									   otherButton:nil
						 informativeTextWithFormat:@"Move the %@ to point to the commit: %@", [ref refishType], subject];
    [alert setShowsSuppressionButton:YES];

	[alert beginSheetModalForWindow:[historyController.repository.windowController window]
					  modalDelegate:self
					 didEndSelector:@selector(acceptDropInfoAlertDidEnd:returnCode:contextInfo:)
						contextInfo:Nil];
    actDropInfo = dropInfo;

	return YES;
}

- (void)acceptDropInfoAlertDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
    [[alert window] orderOut:nil];

	if (returnCode == NSAlertDefaultReturn)
		[self dropRef:actDropInfo];

	if ([[alert suppressionButton] state] == NSOnState)
        [PBGitDefaults suppressDialogWarningForDialog:kDialogAcceptDroppedRef];
}

@end
