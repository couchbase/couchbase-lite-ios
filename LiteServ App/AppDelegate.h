//
//  AppDelegate.h
//  LiteServ App
//
//  Created by Jens Alfke on 9/23/13.
//
//

#import <Cocoa/Cocoa.h>

@interface AppDelegate : NSObject <NSApplicationDelegate>
{
    IBOutlet NSMenu* _statusMenu;
}

- (IBAction) about: (id)sender;
- (IBAction) quit: (id)sender;
- (IBAction) openAdmin: (id)sender;
- (IBAction) viewLogs: (id)sender;
- (IBAction) showToolInstaller: (id)sender;

@end
