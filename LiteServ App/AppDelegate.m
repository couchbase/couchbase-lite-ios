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

#import "CouchbaseLite.h"
#import "CBLListener.h"
#import "CBLJSViewCompiler.h"


#define kServerPort 59840


@implementation AppDelegate
{
    NSStatusItem* _statusItem;
}


- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
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


- (void) startLiteServ {
    CBLManager* manager = [CBLManager sharedInstance];

    [CBLView setCompiler: [[CBLJSViewCompiler alloc] init]];

    // Start a listener socket:
    CBLListener* listener = [[CBLListener alloc] initWithManager: manager port: kServerPort];
    NSCAssert(listener!=nil, @"Couldn't create CBLListener");
    // Advertise via Bonjour:
    [listener setBonjourName: @"LiteServ" type: @"_cbl._tcp."];

    NSError* error;
    if (![listener start: &error]) {
        [self fatalError: error];
        exit(1);
    }
    NSLog(@"LiteServ is listening...");
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

    // Create a "cd" command.
    NSString * command = [NSString stringWithFormat: @"curl :%d/", kServerPort];
    [terminal doScript: command in: currentTab];

    // Activate the Terminal. Hopefully, the new window is already open and
    // is will be brought to the front.
    [terminal activate];

}


-(IBAction) showToolInstaller: (id)sender {
    [ToolInstallController show];
}

@end
