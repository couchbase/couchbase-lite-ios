//
//  PrivilegedInstall.h
//  Couchbase Server
//
//  Created by Jens Alfke on 6/14/12.
//  Copyright (c) 2012 NorthScale. All rights reserved.
//

#import <Foundation/Foundation.h>

BOOL PrivilegedInstall(NSArray* sourceFiles, NSString* destinationDir,
                       NSError** outError);
BOOL UnprivilegedInstall(NSArray* sourceFiles, NSString* destinationDir,
                         NSError** outError);
