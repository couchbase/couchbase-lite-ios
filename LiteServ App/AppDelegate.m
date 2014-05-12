//
//  AppDelegate.m
//  LiteServ App
//
//  Created by Jens Alfke on 9/23/13.
//
//

#import "AppDelegate.h"
#import "ToolInstallController.h"
#import "Terminal.h"
#import "LoggingMode.h"

#import "CouchbaseLite.h"
#import "CBLListener.h"
#import "CBLJSViewCompiler.h"


#define kServerPort 59840


@implementation AppDelegate
{
    BOOL _loggingToFile;
    NSStatusItem* _statusItem;
    CBLManager* _manager;
    CBLListener* _listener;
}


- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    _loggingToFile = [self redirectLogging];

    _statusItem=[[NSStatusBar systemStatusBar] statusItemWithLength: NSSquareStatusItemLength];
    NSImage *statusIcon = [NSImage imageNamed:@"LiteServ_MenubarIcon.png"];
    statusIcon.size = NSMakeSize(16,16);
    _statusItem.image = statusIcon;
    _statusItem.menu = _statusMenu;
    _statusItem.enabled = YES;
    _statusItem.highlightMode = YES;

    [self startLiteServ];

    //[ToolInstallController showIfFirstRun];
}


- (NSString*) logFile {
    return [NSHomeDirectory() stringByAppendingPathComponent: @"Library/Logs/LiteServ.log"];
}


- (BOOL) redirectLogging {
    if (GetLoggingMode() != kLoggingToNowhere)
        return NO;
    freopen(self.logFile.fileSystemRepresentation, "a", stderr);
    fputs("\n\n\n\n", stderr);
    fflush(stderr);
    return YES;
}


- (void) startLiteServ {
    NSLog(@"Starting LiteServ.app ...");

    [CBLView setCompiler: [[CBLJSViewCompiler alloc] init]];

    // Start a listener socket:
    _manager = [CBLManager sharedInstance];
    _listener = [[CBLListener alloc] initWithManager: _manager port: kServerPort];
    NSCAssert(_listener!=nil, @"Couldn't create CBLListener");
    // Advertise via Bonjour:
    //[listener setBonjourName: @"LiteServ" type: @"_cbl._tcp."];

    NSError* error;
    if (![_listener start: &error]) {
        [self fatalError: error];
    }
    NSLog(@"LiteServ is listening on port %d", _listener.port);
}


- (void) fatalError: (NSError*)error {
    NSAlert* alert = [NSAlert alertWithMessageText: @"Couldn't start LiteServ"
                                     defaultButton: @"Quit"
                                   alternateButton: nil otherButton: nil
                         informativeTextWithFormat: @"A fatal error occurred: %@",
                                                      error.localizedDescription];
    [alert runModal];
    [NSApp terminate: self];
}


- (IBAction) about:(id)sender {
    [NSApp orderFrontStandardAboutPanel: self];
}


- (IBAction) quit:(id)sender {
    NSLog(@"Quitting LiteServ.app");

    [_listener stop];

    [(NSApplication*)NSApp terminate: self];
}


- (IBAction) openAdmin: (id)sender {
    // Terminal
    // Code from John Daniel - ShellHere
    TerminalApplication * terminal = [SBApplication applicationWithBundleIdentifier: @"com.apple.Terminal"];
	BOOL terminalWasRunning = [terminal isRunning];

    // Get the Terminal windows.
    SBElementArray * terminalWindows = [terminal windows];

    TerminalTab * currentTab = nil;

    // If there is only a single window with a single tab, Terminal may
    // have been just launched. If so, I want to use the new window.
	// (This prevents two windows from being created.)
    if(!terminalWasRunning) {
        for(TerminalWindow * terminalWindow in terminalWindows) {
		    SBElementArray * windowTabs = [terminalWindow tabs];
            for(TerminalTab * tab in windowTabs) {
                currentTab = tab;
            }
        }
    }

    // Run the command.
    NSString * command = [NSString stringWithFormat: @"curl :%d/", kServerPort];
    [terminal doScript: command in: currentTab];

    // Activate the Terminal. Hopefully, the new window is already open and
    // is will be brought to the front.
    [terminal activate];

}


- (IBAction) viewLogs: (id)sender {
    [[NSWorkspace sharedWorkspace] openFile: self.logFile];
}


-(IBAction) showToolInstaller: (id)sender {
    [ToolInstallController show];
}


- (BOOL) validateUserInterfaceItem: (id<NSValidatedUserInterfaceItem>)item {
    if (item.action == @selector(viewLogs:)) {
        return _loggingToFile;
    } else {
        return YES;
    }
}


@end
