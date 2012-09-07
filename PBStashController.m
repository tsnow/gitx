//
//  PBStashController.m
//  GitX
//
//  Created by Tomasz Krasnyk on 10-11-27.
//  Copyright (c) 2010 __MyCompanyName__. All rights reserved.
//

#import "PBStashController.h"
#import "PBGitRepository.h"
#import "PBCommand.h"
#import "PBCommandWithParameter.h"

static NSString * const kCommandName = @"stash";

@interface PBStashController()
@property (nonatomic, retain) NSArray *stashes;
@end



@implementation PBStashController
@synthesize stashes;

- (id) initWithRepository:(PBGitRepository *) repo {
    if ((self = [super init])){
        repository = repo;
    }
    return self;
}


- (void) reload {
    NSArray *arguments = @[kCommandName, @"list"];
	NSString *output = [repository outputInWorkdirForArguments:arguments];
	NSArray *lines = [output componentsSeparatedByString:@"\n"];
	
	NSMutableArray *loadedStashes = [[NSMutableArray alloc] initWithCapacity:[lines count]];
	
	for (NSString *stashLine in lines) {
		if ([stashLine length] == 0)
			continue;
		PBGitStash *stash = [[PBGitStash alloc] initWithRawStashLine:stashLine];
		if (stash != nil)
			[loadedStashes addObject:stash];
	}
	
	self.stashes = loadedStashes;
}

#pragma mark Actions

- (void) stashLocalChanges {
	NSArray *args = @[kCommandName];
	PBCommand *command = [[PBCommand alloc] initWithDisplayName:@"Stash local changes..." parameters:args repository:repository];
	command.commandTitle = command.displayName;
	command.commandDescription = @"Stashing local changes";
	
	PBCommandWithParameter *cmd = [[PBCommandWithParameter alloc] initWithCommand:command parameterName:@"save" parameterDisplayName:@"Stash message (optional)"];
	
	[cmd invoke];
}

- (void) clearAllStashes {
	PBCommand *command = [[PBCommand alloc] initWithDisplayName:@"Clear stashes" parameters:@[kCommandName, @"clear"] repository:repository];
	command.commandTitle = command.displayName;
	command.commandDescription = @"Clearing stashes";
	[command invoke];
}

#pragma mark Menu

- (NSArray *) menu {
	NSMutableArray *array = [[NSMutableArray alloc] init];
	
	NSMenuItem *stashChanges = [[NSMenuItem alloc] initWithTitle:@"Stash local changes..." action:@selector(stashLocalChanges) keyEquivalent:@""];
	[stashChanges setTarget:self];
	NSMenuItem *clearStashes = [[NSMenuItem alloc] initWithTitle:@"Clear stashes" action:@selector(clearAllStashes) keyEquivalent:@""];
	[clearStashes setTarget:self];
	
	[array addObject:stashChanges];
	[array addObject:clearStashes];
	
	return array;
}

- (BOOL) validateMenuItem:(NSMenuItem *) item {
	SEL action = [item action];
	BOOL shouldBeEnabled = YES;
	
	if (action == @selector(stashLocalChanges)) {
		//TODO: check if we have unstaged changes
	} else if (action == @selector(clearAllStashes)) {
		shouldBeEnabled = [self.stashes count] > 0;
	}
	
	return shouldBeEnabled;
}


@end
