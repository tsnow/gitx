//
//  PBGitSidebar.m
//  GitX
//
//  Created by Pieter de Bie on 9/8/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "PBGitSidebarController.h"
#import "PBSourceViewItems.h"
#import "PBGitHistoryController.h"
#import "PBGitCommitController.h"
#import "PBRefController.h"
#import "PBSourceViewCell.h"
#import "NSOutlineViewExt.h"
#import "PBAddRemoteSheet.h"
#import "PBGitDefaults.h"
#import "PBHistorySearchController.h"
#import "PBGitMenuItem.h"

#import "PBStashCommandFactory.h"
#import "PBRemoteCommandFactory.h"
#import "PBCommandMenuItem.h"
#import "PBGitStash.h"
#import "PBGitSubmodule.h"
#import "PBSubmoduleController.h"
#import "PBStashContentController.h"

NSString *kObservingContextStashes = @"stashesChanged";
NSString *kObservingContextSubmodules = @"submodulesChanged";

@interface PBGitSidebarController ()

- (void)populateList;
- (void)addRevSpec:(PBGitRevSpecifier *)revSpec;
- (PBSourceViewItem *) itemForRev:(PBGitRevSpecifier *)rev;
- (void) removeRevSpec:(PBGitRevSpecifier *)rev;
- (void) updateActionMenu;
- (void) updateRemoteControls;
- (void) updateMetaDataForBranches;
@end

@implementation PBGitSidebarController
@synthesize items;
@synthesize sourceListControlsView;
@synthesize historyViewController;
@synthesize commitViewController;
@synthesize stashViewController;

- (id)initWithRepository:(PBGitRepository *)theRepository superController:(PBGitWindowController *)controller
{
	self = [super initWithRepository:theRepository superController:controller];
	[sourceView setDelegate:self];
	items = [NSMutableArray array];
	
	return self;
}

- (void)awakeFromNib
{
	[super awakeFromNib];
	window.contentView = self.view;
	[self populateList];
	
	historyViewController = [[PBGitHistoryController alloc] initWithRepository:repository superController:superController];
	commitViewController = [[PBGitCommitController alloc] initWithRepository:repository superController:superController];
	stashViewController = [[PBStashContentController alloc] initWithRepository:repository superController:superController];
	
	[historyViewController view]; //preload historyViewController so the contextual menus in the sidebar work
	[stashViewController view];
	
	[repository addObserver:self forKeyPath:@"refs" options:0 context:@"updateRefs"];
	[repository addObserver:self forKeyPath:@"currentBranch" options:0 context:@"currentBranchChange"];
	[repository addObserver:self forKeyPath:@"branches" options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:@"branchesModified"];
	[repository addObserver:self forKeyPath:@"stashController.stashes" options:NSKeyValueObservingOptionNew context:(__bridge void *)kObservingContextStashes];
	[repository addObserver:self forKeyPath:@"submoduleController.submodules" options:NSKeyValueObservingOptionNew context:(__bridge void *)kObservingContextSubmodules];
	
	
	[self menuNeedsUpdate:[actionButton menu]];
	
	if ([PBGitDefaults showStageView])
		[self selectStage];
	else
		[self selectCurrentBranch];
	
	[sourceView setDoubleAction:@selector(outlineDoubleClicked)];
	[sourceView setTarget:self];
    [self updateMetaDataForBranches];
    [self evaluateRemoteBadge];
}

- (void)closeView
{
	[historyViewController closeView];
	[commitViewController closeView];
	[stashViewController closeView];
	
    [repository removeObserver:self forKeyPath:@"refs"];
	[repository removeObserver:self forKeyPath:@"currentBranch"];
	[repository removeObserver:self forKeyPath:@"branches"];
	[repository removeObserver:self forKeyPath:@"stashController.stashes"];
	[repository removeObserver:self forKeyPath:@"submoduleController.submodules"];
	
	[super closeView];
}

- (void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if ([@"currentBranchChange" isEqualToString:(__bridge NSString *)context]) {
		[sourceView reloadData];
		[self selectCurrentBranch];
	}else if ([@"branchesModified" isEqualToString:(__bridge NSString *)context]) {
		NSInteger changeKind = [(NSNumber *)change[NSKeyValueChangeKindKey] intValue];
		
		if (changeKind == NSKeyValueChangeInsertion) {
			NSArray *newRevSpecs = change[NSKeyValueChangeNewKey];
			for (PBGitRevSpecifier *rev in newRevSpecs) {
				[self addRevSpec:rev];
				PBSourceViewItem *item = [self itemForRev:rev];
				[sourceView PBExpandItem:item expandParents:YES];
			}
		}
		else if (changeKind == NSKeyValueChangeRemoval) {
			NSArray *removedRevSpecs = change[NSKeyValueChangeOldKey];
			for (PBGitRevSpecifier *rev in removedRevSpecs)
				[self removeRevSpec:rev];
		}
	} else if ([kObservingContextStashes isEqualToString:(__bridge NSString *)context]) {		// isEqualToString: is not needed here
		[stashes.children removeAllObjects];
		NSArray *newStashes = change[NSKeyValueChangeNewKey];
		
		PBGitMenuItem *lastItem = nil;
		for (PBGitStash *stash in newStashes) {
			PBGitMenuItem *item = [[PBGitMenuItem alloc] initWithSourceObject:stash];
			[stashes addChildWithoutSort:item];
			lastItem = item;
		}
		[sourceView reloadData];
		if (lastItem) {
			[sourceView PBExpandItem:lastItem expandParents:YES];
		}
	} else if ([kObservingContextSubmodules isEqualToString:(__bridge NSString *)context]) {
		[submodules.children removeAllObjects];
		[sourceView reloadData]; //reload now otherwise the outline view may crash while loading old objects
		
		NSArray *newSubmodules = change[NSKeyValueChangeNewKey];
		
		for (PBGitSubmodule *submodule in newSubmodules) {
			PBGitMenuItem *item = [[PBGitMenuItem alloc] initWithSourceObject:submodule];
			
			BOOL added = NO;
			for (PBGitMenuItem *addedItems in [submodules children]) {
				if ([[submodule path] hasPrefix:[NSString  stringWithFormat:@"%@/", [(id)[addedItems sourceObject] path]]]) {
					[addedItems addChild:item];
					added = YES;
				}
			}
			if (!added) {
				[submodules addChild:item];
			}
			[sourceView PBExpandItem:item expandParents:YES];
		}
		[sourceView reloadData];
	}else if ([@"updateRefs" isEqualToString:(__bridge NSString *)context]) {
        [self evaluateRemoteBadge];
		[self updateMetaDataForBranches];
	}else{
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}


-(void)updateMetaDataForBranches:(PBSourceViewItem *)theBranches
{
    for(PBGitSVBranchItem* branch in [theBranches children]){
        if([branch isKindOfClass:[PBGitSVBranchItem class]]){
            dispatch_async(PBGetWorkQueue(),^{
                id ahead = [self countCommitsOf:[NSString stringWithFormat:@"origin/%@..%@",branch.revSpecifier,branch.revSpecifier]];
                id behind = [self countCommitsOf:[NSString stringWithFormat:@"%@..origin/%@",branch.revSpecifier,branch.revSpecifier]];
                dispatch_async(dispatch_get_main_queue(),^{
                    [branch setAhead:ahead];
                    [branch setBehind:behind];
                    [branch setIsCheckedOut:[branch.revSpecifier isEqual:[repository headRef]]];
                });
            });
        }else if ([branch isKindOfClass:[PBGitSVFolderItem class]]) {
            [self updateMetaDataForBranches: branch];
        }
    }
}

-(void)updateMetaDataForBranches
{
    [self updateMetaDataForBranches: branches];
}

#pragma mark Badges Methods

-(void)evaluateRemoteBadge
{
    for(PBGitSVRemoteItem* remote in [remotes children]){
        if([remote isKindOfClass:[PBGitSVRemoteItem class]]) {
            if(remote.loading==NO){
                remote.loading = YES;
                DLog(@"remote.title=%@",[remote title]);
                dispatch_async(PBGetWorkQueue(), ^{
                    bool needsFetch = [self remoteNeedFetch:[remote title]];
                    if(needsFetch){
                        NSUserNotification *notification = [[NSUserNotification alloc] init];
                        notification.title=@"GitX";
                        notification.informativeText=[NSString stringWithFormat:@"remote '%@' needs a pull",[remote title]];
                        notification.soundName=NSUserNotificationDefaultSoundName;
                        NSUserNotificationCenter *center = [NSUserNotificationCenter defaultUserNotificationCenter];
                        [center deliverNotification:notification];
                    }
                    [remote setAlert:needsFetch];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [sourceView setNeedsDisplay];
                    });
                    remote.loading = NO;
                });
            }
        }
	}
}

-(NSNumber *)countCommitsOf:(NSString *)range
{
	NSArray *args = @[@"rev-list", range];
	int ret;
	NSString *o = [repository outputForArguments:args retValue:&ret];
	if ((ret!=0) || ([o length]==0)) {
		return NULL;
	}
	NSArray *commits = [o componentsSeparatedByString:@"\n"];
	return [NSNumber numberWithInt:[commits count]];
}


-(bool)remoteNeedFetch:(NSString *)remote
{
	int ret;
	NSArray *args = @[@"fetch", @"--dry-run", remote];
	NSString *o = [repository outputForArguments:args retValue:&ret];
	return ((ret==0) && ([o length]!=0));
}

#pragma mark -----

- (PBSourceViewItem *) selectedItem
{
	NSInteger index = [sourceView selectedRow];
	PBSourceViewItem *item = [sourceView itemAtRow:index];
	
	return item;
}

- (void) selectStage
{
	NSIndexSet *index = [NSIndexSet indexSetWithIndex:[sourceView rowForItem:stage]];
	[sourceView selectRowIndexes:index byExtendingSelection:NO];
}

- (void) selectCurrentBranch
{
	PBGitRevSpecifier *rev = repository.currentBranch;
	if (!rev) {
		[repository reloadRefs];
		[repository readCurrentBranch];
		return;
	}
	
	PBSourceViewItem *item = nil;
	for (PBSourceViewItem *it in items)
		if ( (item = [it findRev:rev]) != nil )
			break;
	
	if (!item) {
		[self addRevSpec:rev];
		// Try to find the just added item again.
		// TODO: refactor with above.
		for (PBSourceViewItem *it in items)
			if ( (item = [it findRev:rev]) != nil )
				break;
	}
	
	[sourceView PBExpandItem:item expandParents:YES];
	NSIndexSet *index = [NSIndexSet indexSetWithIndex:[sourceView rowForItem:item]];
	
    // Select the corresponding commit in the history view
    if ([rev isSimpleRef])
        [historyViewController selectCommit:[repository shaForRef:[rev ref]]];
    
	[sourceView selectRowIndexes:index byExtendingSelection:NO];
}

- (void) outlineDoubleClicked {
	PBSourceViewItem *item = [self selectedItem];
	if ([item isKindOfClass:[PBGitMenuItem class]]) {
		PBGitMenuItem *sidebarItem = (PBGitMenuItem *) item;
		id<PBPresentable> sourceObject = [sidebarItem sourceObject];
		if ([sourceObject isKindOfClass:[PBGitSubmodule class]]) {
			[[repository.submoduleController defaultCommandForSubmodule:(id)sourceObject] invoke];
		}
    } else if ([item isKindOfClass:[PBGitSVBranchItem class]]) {
        [repository checkoutRefish:item.ref];
    }
}

- (PBSourceViewItem *) itemForRev:(PBGitRevSpecifier *)rev
{
	PBSourceViewItem *foundItem = nil;
	for (PBSourceViewItem *item in items)
		if ( (foundItem = [item findRev:rev]) != nil )
			return foundItem;
	return nil;
}

- (void)addRevSpec:(PBGitRevSpecifier *)rev
{
	if (![rev isSimpleRef]) {
		[others addChild:[PBSourceViewItem itemWithRevSpec:rev]];
		[sourceView reloadData];
		return;
	}
	
	NSArray *pathComponents = [[rev simpleRef] componentsSeparatedByString:@"/"];
	if ([pathComponents count] < 2)
		[branches addChild:[PBSourceViewItem itemWithRevSpec:rev]];
	else if ([pathComponents[1] isEqualToString:@"heads"])
		[branches addRev:rev toPath:[pathComponents subarrayWithRange:NSMakeRange(2, [pathComponents count] - 2)]];
	else if ([[rev simpleRef] hasPrefix:@"refs/tags/"])
		[tags addRev:rev toPath:[pathComponents subarrayWithRange:NSMakeRange(2, [pathComponents count] - 2)]];
	else if ([[rev simpleRef] hasPrefix:@"refs/remotes/"])
		[remotes addRev:rev toPath:[pathComponents subarrayWithRange:NSMakeRange(2, [pathComponents count] - 2)]];
	
	[sourceView reloadData];
}

- (void) removeRevSpec:(PBGitRevSpecifier *)rev
{
	PBSourceViewItem *item = [self itemForRev:rev];
	
	if (!item)
		return;
	
	PBSourceViewItem *parent = item.parent;
	[parent removeChild:item];
	[sourceView reloadData];
}

- (void)setHistorySearch:(NSString *)searchString mode:(NSInteger)mode
{
	[historyViewController.searchController setHistorySearch:searchString mode:mode];
}

#pragma mark NSOutlineView delegate methods

- (void)outlineViewSelectionDidChange:(NSNotification *)notification
{
	NSInteger index = [sourceView selectedRow];
	PBSourceViewItem *item = [sourceView itemAtRow:index];
	
	if ([item revSpecifier]) {
		if (![repository.currentBranch isEqual:[item revSpecifier]])
			repository.currentBranch = [item revSpecifier];
		[superController changeContentController:historyViewController];
		[PBGitDefaults setShowStageView:NO];
	}
	
	if (item == stage) {
		[superController changeContentController:commitViewController];
		[PBGitDefaults setShowStageView:YES];
	}
	
	if ([item parent] == stashes) {
		[superController changeContentController:stashViewController];
		[PBGitDefaults setShowStageView:NO];
		[stashViewController showStash:(PBGitStash*)[(PBGitMenuItem*)item sourceObject]];
	}
    
	[self updateActionMenu];
	[self updateRemoteControls];
}

#pragma mark NSOutlineView delegate methods
- (BOOL)outlineView:(NSOutlineView *)outlineView isGroupItem:(id)item
{
	return [item isGroupItem];
}

- (void)outlineView:(NSOutlineView *)outlineView willDisplayCell:(PBSourceViewCell *)cell forTableColumn:(NSTableColumn *)tableColumn item:(PBSourceViewItem *)item
{
	BOOL showsActionButton = NO;
	if ([item respondsToSelector:@selector(showsActionButton)]) {
		showsActionButton = [item showsActionButton];
		[cell setTarget:self];
		cell.iInfoButtonAction = @selector(infoButtonAction:);
	}
	cell.showsActionButton = showsActionButton;
	
	[cell setBadge:[item badge]];
	[cell setImage:[item icon]];
}

- (NSString *)outlineView:(NSOutlineView *)outlineView toolTipForCell:(NSCell *)cell rect:(NSRectPointer)rect tableColumn:(NSTableColumn *)tc item:(id)item mouseLocation:(NSPoint)mouseLocation
{
	return [item helpText];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectItem:(id)item
{
	return ![item isGroupItem];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldTrackCell:(NSCell *)cell forTableColumn:(NSTableColumn *)tableColumn item:(id)item {
	return [item isGroupItem];
}

//
// The next method is necessary to hide the triangle for uncollapsible items
// That is, items which should always be displayed, such as the Project group.
// This also moves the group item to the left edge.
- (BOOL) outlineView:(NSOutlineView *)outlineView shouldShowOutlineCellForItem:(id)item
{
	return ![item isUncollapsible];
}

- (NSString*) helpTextForRemoteURLs:(NSArray*)urls
{
	NSString *fetchURL = urls[0];
	NSString *pushURL = urls[1];
    
	if ([fetchURL isEqual:pushURL])
		return fetchURL;
	else	// Down triangle for fetch, up triangle for push
		return [NSString stringWithFormat:@"\u25bc %@\n\u25b2 %@", fetchURL, pushURL];
}

- (void)populateList
{
	PBSourceViewItem *project = [PBSourceViewItem groupItemWithTitle:[repository projectName]];
	project.showsActionButton = YES;
	project.isUncollapsible = YES;
	
	stage = [PBGitSVStageItem stageItem];
	[project addChild:stage];
	
	
	branches = [PBSourceViewItem groupItemWithTitle:@"Branches"];
	remotes = [PBSourceViewItem groupItemWithTitle:@"Remotes"];
	tags = [PBSourceViewItem groupItemWithTitle:@"Tags"];
	others = [PBSourceViewItem groupItemWithTitle:@"Other"];
	stashes = [PBSourceViewItem groupItemWithTitle:@"Stashes"];
	submodules = [PBSourceViewItem groupItemWithTitle:@"Submodules"];
	
	for (PBGitRevSpecifier *rev in repository.branches)
		[self addRevSpec:rev];
	for (PBGitSVRemoteItem *remote in remotes.children)
		[remote setHelpText:[self helpTextForRemoteURLs:[[self repository] URLsForRemote:[remote title]]]];
	
	[items addObject:project];
	[items addObject:branches];
	[items addObject:remotes];
	[items addObject:tags];
	[items addObject:others];
	[items addObject:stashes];
	[items addObject:submodules];
	
	[sourceView reloadData];
	[sourceView expandItem:project];
	[sourceView expandItem:branches expandChildren:YES];
	[sourceView expandItem:remotes];
	//[sourceView expandItem:submodules expandChildren:YES];
	
	[sourceView reloadItem:nil reloadChildren:YES];
}

#pragma mark NSOutlineView Datasource methods

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
	if (!item)
		return items[index];
	
	return [(PBSourceViewItem *)item children][index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
	return [[(PBSourceViewItem *)item children] count];
}

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
	if (!item)
		return [items count];
	
	return [[(PBSourceViewItem *)item children] count];
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{
	return [(PBSourceViewItem *)item title];
}


#pragma mark Menus

- (void) updateActionMenu
{
	[actionButton setEnabled:([[self selectedItem] ref] != nil)];
}

- (void) addMenuItemsForRef:(PBGitRef *)ref toMenu:(NSMenu *)menu
{
	if (!ref)
		return;
	
	for (NSMenuItem *menuItem in [historyViewController.refController menuItemsForRef:ref])
		[menu addItem:menuItem];
}

- (NSMenuItem *) actionIconItem
{
	NSMenuItem *actionIconItem = [[NSMenuItem alloc] initWithTitle:@"" action:NULL keyEquivalent:@""];
	NSImage *actionIcon = [NSImage imageNamed:@"NSActionTemplate"];
	[actionIcon setSize:NSMakeSize(12, 12)];
	[actionIconItem setImage:actionIcon];
	
	return actionIconItem;
}

- (NSMenu *) menuForRow:(NSInteger)row
{
	if (row == 0) {
		return [historyViewController.repository menu];
	}
	PBSourceViewItem *viewItem = [sourceView itemAtRow:row];
	if ([viewItem isKindOfClass:[PBGitMenuItem class]]) {
		PBGitMenuItem *stashItem = (PBGitMenuItem *) viewItem;
		NSMutableArray *commands = [[NSMutableArray alloc] init];
		[commands addObjectsFromArray:[PBStashCommandFactory commandsForObject:[stashItem sourceObject] repository:historyViewController.repository]];
		[commands addObjectsFromArray:[PBRemoteCommandFactory commandsForObject:[stashItem sourceObject] repository:historyViewController.repository]];
		if (!commands) {
			return nil;
		}
		NSMenu *menu = [[NSMenu alloc] init];
		[menu setAutoenablesItems:NO];
		for (PBCommand *command in commands) {
			PBCommandMenuItem *item = [[PBCommandMenuItem alloc] initWithCommand:command];
			[menu addItem:item];
		}
		return menu;
	}
	
	PBGitRef *ref = [viewItem ref];
	if (!ref)
		return nil;
	
	NSMenu *menu = [[NSMenu alloc] init];
	[menu setAutoenablesItems:NO];
	[self addMenuItemsForRef:ref toMenu:menu];
	
	return menu;
}

// delegate of the action menu
- (void) menuNeedsUpdate:(NSMenu *)menu
{
	[actionButton removeAllItems];
	[menu addItem:[self actionIconItem]];
	
	PBGitRef *ref = [[self selectedItem] ref];
	[self addMenuItemsForRef:ref toMenu:menu];
}


#pragma mark Remote controls

enum  {
	kAddRemoteSegment = 0,
	kFetchSegment,
	kPullSegment,
	kPushSegment
};

- (void) updateRemoteControls
{
	BOOL hasRemote = NO;
	
	PBGitRef *ref = [[self selectedItem] ref];
	if ([ref isRemote] || ([ref isBranch] && [[repository remoteRefForBranch:ref error:NULL] remoteName]))
		hasRemote = YES;
	
	[remoteControls setEnabled:hasRemote forSegment:kFetchSegment];
	[remoteControls setEnabled:hasRemote forSegment:kPullSegment];
	[remoteControls setEnabled:hasRemote forSegment:kPushSegment];
    
    // get config
    BOOL hasSVN = [repository hasSvnRemote];
    [svnFetchButton setEnabled:hasSVN];
    [svnFetchButton setHidden:!hasSVN];
    [svnRebaseButton setEnabled:hasSVN];
    [svnRebaseButton setHidden:!hasSVN];
    [svnDcommitButton setEnabled:hasSVN];
    [svnDcommitButton setHidden:!hasSVN];
}

- (IBAction) fetchPullPushAction:(id)sender
{
	NSInteger selectedSegment = [sender selectedSegment];
	
	if (selectedSegment == kAddRemoteSegment) {
		[PBAddRemoteSheet beginAddRemoteSheetForRepository:repository withRemoteURL:Nil];
		return;
	}
	
	NSInteger index = [sourceView selectedRow];
	PBSourceViewItem *item = [sourceView itemAtRow:index];
	PBGitRef *ref = [[item revSpecifier] ref];
	
	if (!ref && (item.parent == remotes))
		ref = [PBGitRef refFromString:[kGitXRemoteRefPrefix stringByAppendingString:[item title]]];
	
	if (![ref isRemote] && ![ref isBranch])
		return;
	
	PBGitRef *remoteRef = [repository remoteRefForBranch:ref error:NULL];
	if (!remoteRef)
		return;
	
	if (selectedSegment == kFetchSegment)
		[repository beginFetchFromRemoteForRef:ref];
	else if (selectedSegment == kPullSegment)
		[repository beginPullFromRemote:remoteRef forRef:ref];
	else if (selectedSegment == kPushSegment) {
		if ([ref isRemote])
			[historyViewController.refController showConfirmPushRefSheet:nil remote:remoteRef];
		else if ([ref isBranch])
			[historyViewController.refController showConfirmPushRefSheet:ref remote:remoteRef];
	}
}

- (IBAction) svnFetch:(id)sender
{
    [repository svnFetch:nil];
}

- (IBAction) svnRebase:(id)sender
{
    printf("git svn rebase");
    [repository svnRebase:nil];
}

- (IBAction) svnDcommit:(id)sender
{
    printf("git svn dcommit");
    [repository svnDcommit:nil];
}

@end
