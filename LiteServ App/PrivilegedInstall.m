//
//  PrivilegedInstall.m
//  Couchbase Server
//
//  Created by Jens Alfke on 6/14/12.
//  Copyright (c) 2012-2013 Couchbase. All rights reserved.
//
//  Adapted from Listing 2-17 in the Authorization Services Programming Guide

#import "PrivilegedInstall.h"

#include <Security/Authorization.h>
#include <Security/AuthorizationTags.h>


BOOL PrivilegedInstall(NSArray* sourceFiles, NSString* destinationDir, NSError** outError) {
    NSCParameterAssert(sourceFiles);
    NSCParameterAssert(destinationDir);

    OSStatus myStatus;
    AuthorizationFlags myFlags = kAuthorizationFlagDefaults;
    AuthorizationRef myAuthorizationRef;

    myStatus = AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment,
                                   myFlags, &myAuthorizationRef);
    if (myStatus == errAuthorizationSuccess) {
        {
            AuthorizationItem myItems = {kAuthorizationRightExecute, 0, NULL, 0};
            AuthorizationRights myRights = {1, &myItems};

            myFlags = kAuthorizationFlagDefaults |
                      kAuthorizationFlagInteractionAllowed |
                      kAuthorizationFlagPreAuthorize |
                      kAuthorizationFlagExtendRights;
            myStatus = AuthorizationCopyRights (myAuthorizationRef, &myRights, NULL, myFlags, NULL );
        }

        if (myStatus == errAuthorizationSuccess) {
            const char myToolPath[] = "/bin/ln";
            const char *myArguments[sourceFiles.count + 3];
            int myArgc = 0;
            myArguments[myArgc++] = "-sfh";
            for (NSString* sourceFile in sourceFiles) {
                myArguments[myArgc++] = [sourceFile UTF8String];
            }
            myArguments[myArgc++] = [destinationDir UTF8String];
            myArguments[myArgc] = NULL;

            myFlags = kAuthorizationFlagDefaults;
            //TODO: This function is deprecated
            myStatus = AuthorizationExecuteWithPrivileges(myAuthorizationRef, myToolPath, myFlags,
                                                          (char* const*)myArguments,
                                                          NULL);
        }

        AuthorizationFree (myAuthorizationRef, kAuthorizationFlagDefaults);
    }
    
    if (myStatus == noErr) {
        return YES;
    }
    if (outError) {
        *outError = [NSError errorWithDomain: NSOSStatusErrorDomain code: myStatus userInfo: nil];
    }
    return NO;
}


BOOL UnprivilegedInstall(NSArray* sourceFiles, NSString* destinationDir, NSError** outError)
{
    NSFileManager* fmgr = [NSFileManager defaultManager];
    for (NSString* sourceFile in sourceFiles) {
        NSString* sourceName = sourceFile.lastPathComponent;
        NSString* destinationFile = [destinationDir stringByAppendingPathComponent: sourceName];
        [fmgr removeItemAtPath: destinationFile error: nil];
        if (![fmgr createSymbolicLinkAtPath: destinationFile
                        withDestinationPath: sourceFile
                                      error: outError]) {
            return NO;
        }
    }
    return YES;
}
