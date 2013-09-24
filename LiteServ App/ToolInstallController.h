//
//  ToolInstallController.h
//  Couchbase Server
//
//  Created by Jens Alfke on 6/14/12.
//  Copyright (c) 2012 NorthScale. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface ToolInstallController : NSWindowController
{
    IBOutlet NSTextField* _toolNameListField;
    IBOutlet NSTextField* _internalPathField;
    IBOutlet NSPopUpButton* _destinationPopUp;
    
    NSString* _srcDir;
    NSMutableArray* _toolNames;
}

+ (ToolInstallController*) showIfFirstRun;
+ (ToolInstallController*) show;

- (IBAction) install:(id)sender;
- (IBAction) cancel:(id)sender;

@end
