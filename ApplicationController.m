//
//  GitTest_AppDelegate.m
//  GitTest
//
//  Created by Pieter de Bie on 13-06-08.
//  Copyright __MyCompanyName__ 2008 . All rights reserved.
//

#import "ApplicationController.h"
#import "PBGitRevisionCell.h"
#import "PBGitWindowController.h"
#import "PBRepositoryDocumentController.h"
#import "PBServicesController.h"
#import "PBGitXProtocol.h"
#import "PBPrefsWindowController.h"
#import "PBNSURLPathUserDefaultsTransfomer.h"
#import "PBGitDefaults.h"
#import "PBCloneRepositoryPanel.h"
#import "AIURLAdditions.h"
#import "PBGitRepository.h"

@interface ApplicationController ()
- (void) cleanUpRemotesOnError;
@property (retain, nonatomic) NSUndoManager *undoManager;

@end


@implementation ApplicationController

- (ApplicationController*)init
{
#ifdef DEBUG_BUILD
	[NSApp activateIgnoringOtherApps:YES];
#endif

	if(!(self = [super init]))
		return nil;

	/* Value Transformers */
	NSValueTransformer *transformer = [[PBNSURLPathUserDefaultsTransfomer alloc] init];
	[NSValueTransformer setValueTransformer:transformer forName:@"PBNSURLPathUserDefaultsTransfomer"];
	
	// Make sure the PBGitDefaults is initialized, by calling a random method
	[PBGitDefaults class];
	return self;
}

- (void)registerServices
{
	// Register URL
	[NSURLProtocol registerClass:[PBGitXProtocol class]];

	// Register the service class
	PBServicesController *services = [[PBServicesController alloc] init];
	[NSApp setServicesProvider:services];

	// Force update the services menu if we have a new services version
	int serviceVersion = [[NSUserDefaults standardUserDefaults] integerForKey:@"Services Version"];
	if (serviceVersion < 2)
	{
		DLog(@"Updating services menu…");
		NSUpdateDynamicServices();
		[[NSUserDefaults standardUserDefaults] setInteger:2 forKey:@"Services Version"];
	}
}

- (void)applicationWillFinishLaunching:(NSNotification*)notification
{
    [[NSAppleEventManager sharedAppleEventManager] setEventHandler:self
                                                       andSelector:@selector(getUrl:withReplyEvent:)
                                                     forEventClass:kInternetEventClass
                                                        andEventID:kAEGetURL];
}
 
- (void)applicationDidFinishLaunching:(NSNotification*)notification
{
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(getArguments:) name:@"GitCommandSent" object:Nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(cleanGitAfterErrorMessage:) name:@"ErrorMessageDidEnd" object:Nil];
     
    if ([PBGitDefaults useAskPasswd]) {
	// Make sure Git's SSH password requests get forwarded to our little UI tool:
	setenv( "SSH_ASKPASS", [[[NSBundle mainBundle] pathForResource: @"gitx_askpasswd" ofType: @""] UTF8String], 1 );
	setenv( "DISPLAY", "localhost:0", 1 );
    }
       
	[self registerServices];

    BOOL hasOpenedDocuments = NO;
    NSArray *launchedDocuments = [[[PBRepositoryDocumentController sharedDocumentController] documents] copy];
    
	// Only try to open a default document if there are no documents open already.
	// For example, the application might have been launched by double-clicking a .git repository,
	// or by dragging a folder to the app icon
	if ([launchedDocuments count])
		hasOpenedDocuments = YES;

    // open any documents that were open the last time the app quit
    if ([PBGitDefaults openPreviousDocumentsOnLaunch]) {
        for (NSString *path in [PBGitDefaults previousDocumentPaths]) {
            NSURL *url = [NSURL fileURLWithPath:path isDirectory:YES];
            NSError *error = nil;
            if (url && [[PBRepositoryDocumentController sharedDocumentController] openDocumentWithContentsOfURL:url display:YES error:&error])
                hasOpenedDocuments = YES;
        }
    }

	// Try to find the current directory, to open that as a repository
	if ([PBGitDefaults openCurDirOnLaunch] && !hasOpenedDocuments) {
		NSString *curPath = [[[NSProcessInfo processInfo] environment] objectForKey:@"PWD"];
        NSURL *url = nil;
		if (curPath)
			url = [NSURL fileURLWithPath:curPath];
        // Try to open the found URL
        NSError *error = nil;
        if (url && [[PBRepositoryDocumentController sharedDocumentController] openDocumentWithContentsOfURL:url display:YES error:&error])
            hasOpenedDocuments = YES;
	}

    // to bring the launched documents to the front
    for (PBGitRepository *document in launchedDocuments)
        [document showWindows];

	if (![[NSApplication sharedApplication] isActive])
		return;
}

- (void)getUrl:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)replyEvent
{
	NSString *urlString = [[event paramDescriptorForKeyword:keyDirectObject] stringValue];
    NSURL *url = [NSURL URLWithString:urlString];
    
    if ([url.host isEqual:@"clone"]) {
        NSString * repo = [[url queryArgumentForKey:@"repo"] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];

        [self showCloneRepository:self];
        
        [cloneRepositoryPanel.repositoryURL setStringValue:repo];
    }
    
}

- (void) windowWillClose: sender
{
	[firstResponder terminate: sender];
}

- (IBAction)openPreferencesWindow:(id)sender
{
	[[PBPrefsWindowController sharedPrefsWindowController] showWindow:nil];
}

- (IBAction)showAboutPanel:(id)sender
{
	NSString *gitversion = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleGitVersion"];
	NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
	if (gitversion)
		[dict addEntriesFromDictionary:[[NSDictionary alloc] initWithObjectsAndKeys:gitversion, @"Version", nil]];

	[dict addEntriesFromDictionary:[[NSDictionary alloc] initWithObjectsAndKeys:@"GitX (L)", @"ApplicationName", nil]];
	[dict addEntriesFromDictionary:[[NSDictionary alloc] initWithObjectsAndKeys:@"(c) Pieter de Bie,2008\n(c) German Laullon,2011\nAnd more...", @"Copyright", nil]];

	#ifdef DEBUG_BUILD
		[dict addEntriesFromDictionary:[[NSDictionary alloc] initWithObjectsAndKeys:@"GitX (DEBUG)", @"ApplicationName", nil]];
	#endif

	[NSApp orderFrontStandardAboutPanelWithOptions:dict];
}

- (IBAction) showCloneRepository:(id)sender
{
	if (!cloneRepositoryPanel)
		cloneRepositoryPanel = [PBCloneRepositoryPanel panel];

	[cloneRepositoryPanel showWindow:self];
}

- (IBAction)installCliTool:(id)sender;
{
	BOOL success               = NO;
	NSString* installationPath = @"/usr/local/bin/";
	NSString* installationName = @"gitx";
	NSString* toolPath         = [[NSBundle mainBundle] pathForResource:@"gitx" ofType:@""];
	if (toolPath) {
		AuthorizationRef auth;
		if (AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment, kAuthorizationFlagDefaults, &auth) == errAuthorizationSuccess) {
			char const* mkdir_arg[] = { "-p", [installationPath UTF8String], NULL};
			char const* mkdir	= "/bin/mkdir";
			AuthorizationExecuteWithPrivileges(auth, mkdir, kAuthorizationFlagDefaults, (char**)mkdir_arg, NULL);
			char const* arguments[] = { "-f", "-s", [toolPath UTF8String], [[installationPath stringByAppendingString: installationName] UTF8String],  NULL };
			char const* helperTool  = "/bin/ln";
			if (AuthorizationExecuteWithPrivileges(auth, helperTool, kAuthorizationFlagDefaults, (char**)arguments, NULL) == errAuthorizationSuccess) {
				int status;
				int pid = wait(&status);
				if (pid != -1 && WIFEXITED(status) && WEXITSTATUS(status) == 0)
					success = true;
				else
					errno = WEXITSTATUS(status);
			}

			AuthorizationFree(auth, kAuthorizationFlagDefaults);
		}
	}

	if (success) {
		[[NSAlert alertWithMessageText:@"Installation Complete"
	                    defaultButton:nil
	                  alternateButton:nil
	                      otherButton:nil
	        informativeTextWithFormat:@"The gitx tool has been installed to %@", installationPath] runModal];
	} else {
		[[NSAlert alertWithMessageText:@"Installation Failed"
	                    defaultButton:nil
	                  alternateButton:nil
	                      otherButton:nil
	        informativeTextWithFormat:@"Installation to %@ failed", installationPath] runModal];
	}
}

/**
    Returns the support folder for the application, used to store the Core Data
    store file.  This code uses a folder named "GitTest" for
    the content, either in the NSApplicationSupportDirectory location or (if the
    former cannot be found), the system's temporary directory.
 */

- (NSString *)applicationSupportFolder {

    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *basePath = ([paths count] > 0) ? [paths objectAtIndex:0] : NSTemporaryDirectory();
    return [basePath stringByAppendingPathComponent:@"GitTest"];
}



/**
    Returns the NSUndoManager for the application.  
 */
 
- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)window {
    return self.undoManager;
}


/**
    Performs the save action for the application, which is nothing.
 */
 
- (IBAction) saveAction:(id)sender {

}


/**
    Implementation of the applicationShouldTerminate: method, used here to
    handle the saving of changes in the application managed object context
    before the application terminates.
 */
 
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {

    int reply = NSTerminateNow;
    

    return reply;
}

- (void)applicationWillTerminate:(NSNotification *)aNotification
{
	[PBGitDefaults removePreviousDocumentPaths];

	if ([PBGitDefaults openPreviousDocumentsOnLaunch]) {
		NSArray *documents = [[PBRepositoryDocumentController sharedDocumentController] documents];
		if ([documents count] > 0) {
			NSMutableArray *paths = [NSMutableArray array];
			for (PBGitRepository *repository in documents)
				[paths addObject:[repository workingDirectory]];

			[PBGitDefaults setPreviousDocumentPaths:paths];
		}
	}
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender
{
    id dc = [PBRepositoryDocumentController sharedDocumentController];
    
    // Reopen last document if user prefers
    if ([PBGitDefaults showOpenPanelOnLaunch])
    {
        [dc openDocument:self];
    }
    
    return NO;
}


#pragma mark Help menu

- (IBAction)showHelp:(id)sender
{
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://gitx.frim.nl/user_manual.html"]];
}

- (IBAction)reportAProblem:(id)sender
{
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://github.com/laullon/gitx/issues"]];
}


#pragma mark - Observer methods

- (void)getArguments:(NSNotification*)notification
{
    notificationUserInfo = [notification userInfo];
}


- (void)cleanGitAfterErrorMessage:(NSNotification*)notification
{
    // When adding a remote occurs an error the remote
    // will be set on git and has to be removed to clean the remotes list
    [self cleanUpRemotesOnError];
    
    
    
}

#pragma mark - Extensions
- (void) cleanUpRemotesOnError
{    
    // check, if arguments was to add a remote
    if ( ([(NSString*)[notificationUserInfo valueForKey:@"Arg0"] compare:@"remote"] == NSOrderedSame) &&
        ([(NSString*)[notificationUserInfo valueForKey:@"Arg1"] compare:@"add"] == NSOrderedSame)
        )
    {
        PBGitRef *remoteRef = [PBGitRef refFromString:[NSString stringWithFormat:@"%@%@", kGitXRemoteRefPrefix,[notificationUserInfo valueForKey:@"Arg3"]]];
        [[notificationUserInfo valueForKey:@"Repository"] deleteRemote:remoteRef];
    }
}

- (NSUndoManager *)undoManager;
{
	if (!_undoManager) {
		_undoManager = [[NSUndoManager alloc] init];
	}
	return _undoManager;
}

@end
