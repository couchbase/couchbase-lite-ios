//
//  ToolInstallController.m
//  Couchbase Server
//
//  Created by Jens Alfke on 6/14/12.
//  Copyright (c) 2012 NorthScale. All rights reserved.
//

#import "ToolInstallController.h"
#import "PrivilegedInstall.h"


#define kSourceDir @"Contents/Tools"
#define kItemPrefix @""


@interface ToolInstallController ()

@end

@implementation ToolInstallController


static ToolInstallController* sController;


+ (ToolInstallController*) showIfFirstRun {
    if ([[NSUserDefaults standardUserDefaults] boolForKey: @"ToolInstallController_Asked"]) {
        return nil;
    }
    [[NSUserDefaults standardUserDefaults] setBool: YES forKey: @"ToolInstallController_Asked"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    return [self show];
}


+ (ToolInstallController*) show {
    if (!sController) {
        sController = [[self alloc] init];
    }
    [NSApp activateIgnoringOtherApps: YES];
    [sController showWindow:self];
    return sController;
}


- (id)init
{
    self = [super initWithWindowNibName:@"ToolInstallController"];
    if (self) {
        _srcDir = [[[NSBundle mainBundle] bundlePath]
                            stringByAppendingPathComponent: kSourceDir];
        _toolNames = [[NSMutableArray alloc] init];
        for (NSString* item in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:_srcDir
                                                                                   error:nil]) {
            if ([item hasPrefix: kItemPrefix] || kItemPrefix.length == 0)
                [_toolNames addObject:item];
        }
        NSAssert(_toolNames.count > 0, @"No tools in %@ ?", _srcDir);
    }
    return self;
}


- (void)windowDidLoad
{
    [super windowDidLoad];

    _toolNameListField.stringValue = [_toolNames componentsJoinedByString:@", "];
    _internalPathField.stringValue = _srcDir;

    for (NSMenuItem* item in _destinationPopUp.itemArray) {
        NSString* title = item.title;
        NSString* path = [title stringByStandardizingPath];
        BOOL isDir;
        if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir] || !isDir) {
            [_destinationPopUp removeItemWithTitle:title];
        }
    }
    [_destinationPopUp selectItemAtIndex: 0];
}


- (void)windowWillClose:(NSNotification*)n {
    sController = nil;
}


- (IBAction)install:(id)sender {
    NSMutableArray* toolPaths = [NSMutableArray array];
    for (NSString* toolName in _toolNames) {
        [toolPaths addObject: [_srcDir stringByAppendingPathComponent: toolName]];
    }
    NSString* destDir = [_destinationPopUp.selectedItem.title stringByStandardizingPath];
    NSError* error = nil;
    NSLog(@"Copying items to %@: %@", destDir, toolPaths);

    BOOL ok;
    if ([[NSFileManager defaultManager] isWritableFileAtPath: destDir]) {
        ok = UnprivilegedInstall(toolPaths, destDir, &error);
    } else {
        ok = PrivilegedInstall(toolPaths, destDir, &error);
    }

    if (ok) {
        [self close];
    } else if (error.code != errAuthorizationCanceled) {
        NSRunCriticalAlertPanel(@"Failed To Install",
                                @"Error %d copying tools into %@:\n\n%@",
                                @"Sorry", nil, nil,
                                (int)error.code, destDir, error.localizedDescription);
    }
}


- (IBAction)cancel:(id)sender {
    [self close];
}


@end
