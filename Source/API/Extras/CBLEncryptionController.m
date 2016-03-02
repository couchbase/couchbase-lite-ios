//
//  CBLEncryptionController.m
//  Couchbase Lite
//
//  Created by Jens Alfke on 2/13/15.
//  Copyright (c) 2015 Couchbase. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License"); you may not
// use this file except in compliance with the License. You may obtain a copy of
// the License at
//
//   http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
// WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
// License for the specific language governing permissions and limitations under
// the License.

#import "CBLEncryptionController.h"
#import <CouchbaseLite/CouchbaseLite.h>
@import UIKit;
@import LocalAuthentication;


#define LOGGING 0
#define Log if (!LOGGING) ; else NSLog


@implementation CBLEncryptionController
{
    CBLManager *_manager;
    CBLEncryptionControllerCompletion _completion;
}

@synthesize databaseName=_dbName, parentController=_parentController, useTouchID=_useTouchID;


- (instancetype) initWithManager: (CBLManager*)manager databaseName: (NSString*)dbName {
    NSParameterAssert(manager);
    NSParameterAssert(dbName);
    self = [super init];
    if (self) {
        _manager = manager;
        _dbName = dbName.copy;
        _useTouchID = [[self class] isTouchIDAvailable];
    }
    return self;
}


- (instancetype) initWithDatabaseName: (NSString*)dbName {
    return [self initWithManager: [CBLManager sharedInstance] databaseName: dbName];
}


- (instancetype) init NS_UNAVAILABLE {
    NSAssert(NO, @"CBLEncryptionController cannot be initialized with -init");
    return nil;
}


- (void) openDatabaseAsync: (CBLEncryptionControllerCompletion)completion {
    NSAssert(!_completion, @"Already opening a database");
    NSParameterAssert(completion);
    _completion = completion;
    CBLDatabase* db = nil;
    NSError* error = nil;
    BOOL startedAsync = NO;
    if (![_manager databaseExistsNamed: _dbName]) {
        // Database doesn't exist, so ask for a key to create it with:
        if (_useTouchID)
            startedAsync = [self createNewPasswordWithTouchID];
        else
            startedAsync = [self askForPasswordWithPrompt: CBLPasswordPromptCreatePassword
                                                    error: &error];
    } else {
        db = [_manager existingDatabaseNamed: _dbName error: &error];
        if (!db && error.code == 401) {
            // Database exists but we haven't registered the key yet:
            if (_useTouchID)
                startedAsync = [self useExistingPasswordWithTouchID];
            else
                startedAsync = [self askForPasswordWithPrompt: CBLPasswordPromptEnterPassword
                                                        error: &error];
        }
    }

    if (!startedAsync) {
        completion(db, error);
        _completion = nil;
    }
}


// Invokes the completion routine.
- (void) completedWithKey: (id)keyOrPassword orError: (NSError*)error {
    NSAssert(_completion, @"No completion routine");
    CBLDatabase* db = nil;
    if (keyOrPassword) {
        Log(@"EncryptionController: Got database password/key! Opening db...");
        [_manager registerEncryptionKey: keyOrPassword forDatabaseNamed: _dbName];
        db = [_manager databaseNamed: _dbName error: &error];
        Log(@"    db=%@,  error=%@", db, error);
        if (!db && error.code == 401 && !_useTouchID) {
            // Wrong password; let the user retry after a brief delay:
            [_manager registerEncryptionKey: nil forDatabaseNamed: _dbName];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                               [self askForPasswordWithPrompt: CBLPasswordPromptReEnterPassword
                                                        error: NULL];
                           });
            return;
        }
    }
    if (error) {
        Log(@"EncryptionController: Failed with error: %@", error);
    }
    _completion(db, error);
    _completion = nil;
    // Done!
}


#pragma mark - PASSWORDS:
//TODO: Use UIAlertView on iOS 7
//TODO: Mac OS support (using NSAlert?)


// These arrays contain the default (English) versions of localized strings for the password UI.
// The first item of each array is the prefix of the localization key; the actual key looked up
// appends the table index (not counting the first item in the array.) So for example,
// "EncryptionController_Title_0" is for "Enter Password".

static NSString* const kTitleStrings[] = { @"CBLEncryptionController_Title_",  // Prefix of loc key
    @"Enter Password",
    @"Re-enter Password",
    @"Create Password",
};

static NSString* const kPromptStrings[] = { @"CBLEncryptionController_Prompt_",
    @"Please enter the database’s password:",
    @"Sorry, wrong password. Try again:",
    @"Choose a password to protect the new database.",
    @"Sorry, the password must be at least six characters. Try again:",
    @"Sorry, the passwords didn't match. Try again:",
    @"Application needs to open an encrypted database." // Used with Touch ID, not passwords
};

static NSString* const kButtonStrings[] = { @"CBLEncryptionController_Button_",
    @"Cancel",
    @"OK",
    @"Create",
};

static NSString* const kPlaceholderStrings[] = { @"CBLEncryptionController_Placeholder_",
    @"password",
    @"repeat password"
};

// Looks up a localized string given the table and the index.
static NSString* localized(NSString* const table[], unsigned index)
{
    NSString* tableName = table[0];
    NSString* locKey = [tableName stringByAppendingFormat: @"%d", index];
    return [[NSBundle mainBundle] localizedStringForKey: locKey value: table[1 + index] table: nil];
}


- (BOOL) askForPasswordWithPrompt: (CBLPasswordPrompt)promptEnum
                            error: (NSError**)outError
{
    if (!_parentController) {
        Log(@"EncryptionController: No parentController, so can't present UI");
        if (outError) {
            *outError = [NSError errorWithDomain: NSOSStatusErrorDomain
                                            code: errSecInteractionNotAllowed
                                        userInfo: nil];
        }
        return NO;
    }
    Log(@"EncryptionController: Prompting user to create a password...");

    BOOL creatingPassword = (promptEnum >= CBLPasswordPromptCreatePassword);
    NSString* title  = localized(kTitleStrings,
                                 MIN(promptEnum, CBLPasswordPromptCreatePassword));
    NSString* prompt = localized(kPromptStrings, promptEnum);

    UIAlertController* alert = [UIAlertController alertControllerWithTitle: title
                                                           message: prompt
                                                    preferredStyle: UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler: ^(UITextField *textField) {
        textField.secureTextEntry = YES;
        textField.placeholder = localized(kPlaceholderStrings, 0);
    }];
    if (creatingPassword) {
        // Add 2nd password field for confirmation:
        [alert addTextFieldWithConfigurationHandler: ^(UITextField *textField) {
            textField.secureTextEntry = YES;
            textField.placeholder = localized(kPlaceholderStrings, 1);
        }];
    }

    [alert addAction: [UIAlertAction actionWithTitle: localized(kButtonStrings, 0)
                                               style: UIAlertActionStyleCancel
                                             handler: ^(UIAlertAction * action)
    {
        // User canceled
        [self completedWithKey: nil orError: nil];
    }]];

    NSString* button = localized(kButtonStrings, (creatingPassword ? 2 : 1));
    [alert addAction: [UIAlertAction actionWithTitle: button
                                               style: UIAlertActionStyleDefault
                                             handler: ^(UIAlertAction * action)
    {
        // Password entered!
        NSString* password = [alert.textFields[0] text];
        if (creatingPassword) {
            // This is a new password, so make sure it's valid:
            int errorPrompt = -1;
            if (![password isEqualToString: [alert.textFields[1] text]])
                errorPrompt = CBLPasswordPromptCreatePasswordMismatch;
            else if (password.length < 6)
                errorPrompt = CBLPasswordPromptCreatePasswordTooShort;
            if (errorPrompt != -1) {
                // Wait a moment to redisplay alert; if we call this synchronously it doesn't work.
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                                   [self askForPasswordWithPrompt: (CBLPasswordPrompt)errorPrompt
                                                            error: NULL];
                });
                return;
            }
        }
        // Now use it to create or open the database:
        [self completedWithKey: password orError: nil];
    }]];

    [_parentController presentViewController: alert animated: YES completion: nil];
    return YES;
}


#pragma mark - TOUCHID:


- (BOOL) createNewPasswordWithTouchID {
    // The Keychain access has to be done from a background thread, in order to leave the main
    // thread free to display the Touch ID prompt.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError* error;
        // Generate a random 256-bit key:
        uint8_t randomData[32];
        SecRandomCopyBytes(kSecRandomDefault, sizeof(randomData), randomData);
        NSData* key = [NSData dataWithBytes: randomData length: sizeof(randomData)];

        if (![self storeKeychainItem: key error: &error]) {
            // If save failed, delete any left-over item and try again:
            [self deleteKeychainItem: NULL];
            if (![self storeKeychainItem: key error: &error]) {
                key = nil;
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            // Back on the main thread:
            [self completedWithKey: key orError: error];
        });
    });
    return YES;
}


- (BOOL) useExistingPasswordWithTouchID {
    // The Keychain access has to be done from a background thread, in order to leave the main
    // thread ready to display the Touch ID prompt.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError* error;
        NSData* key = [self readKeychainItem: &error];
        dispatch_async(dispatch_get_main_queue(), ^{
            // Back on the main thread:
            [self completedWithKey: key orError: error];
        });
    });
    return YES;
}


// The following was adapted from Apple's "KeychainTouchID" sample code:


+ (BOOL) isTouchIDAvailable {
    LAContext *laContext = [[LAContext alloc] init];
    return [laContext canEvaluatePolicy: LAPolicyDeviceOwnerAuthenticationWithBiometrics
                                  error: NULL];
}


- (NSData*) readKeychainItem: (NSError**)outError {
    Log(@"EncryptionController: Getting CBL password from keychain using TouchID...");
    NSString* prompt = localized(kPromptStrings, CBLPasswordPromptTouchID);
    NSDictionary *query = @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                            (__bridge id)kSecAttrService: self.keychainItemName,
                            (__bridge id)kSecReturnData: @YES,
                            (__bridge id)kSecUseOperationPrompt: prompt
                            };
    CFTypeRef cfData = NULL;
    if (!checkStatus(SecItemCopyMatching((__bridge CFDictionaryRef)query, &cfData), outError))
        return nil;
    return CFBridgingRelease(cfData);
}


- (BOOL) storeKeychainItem: (NSData*)keyData error: (NSError**)outError {
    Log(@"EncryptionController: Storing new CBL password in keychain...");
    CFErrorRef cfError = NULL;
    SecAccessControlRef accessCtrl;
    accessCtrl = SecAccessControlCreateWithFlags(kCFAllocatorDefault,
                                                 kSecAttrAccessibleWhenUnlocked,
                                                 kSecAccessControlUserPresence, &cfError);
    if(!accessCtrl) {
        if (outError)
            *outError = CFBridgingRelease(cfError);
        return NO;
    }
    // (If there's already an item stored, we don't want the Touch ID UI to pop up; so use
    // kSecUseNoAuthenticationUI which will cause errSecInteractionNotAllowed to be returned.)
    NSDictionary *attributes = @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                                 (__bridge id)kSecAttrService: self.keychainItemName,
                                 (__bridge id)kSecValueData: keyData,
                                 (__bridge id)kSecUseNoAuthenticationUI: @YES,
                                 (__bridge id)kSecAttrAccessControl: CFBridgingRelease(accessCtrl)};
    return checkStatus(SecItemAdd((__bridge CFDictionaryRef)attributes, nil), outError);
}


- (BOOL) deleteKeychainItem: (NSError**)outError {
    Log(@"EncryptionController: deleting keychain item...");
    NSDictionary *query = @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                            (__bridge id)kSecAttrService: self.keychainItemName };
    return checkStatus(SecItemDelete((__bridge CFDictionaryRef)query), outError);
}


- (NSString*) keychainItemName {
    return [@"CBLDatabase:" stringByAppendingString: _dbName];
}


static BOOL checkStatus(OSStatus status, NSError** outError) {
    if (status == noErr)
        return YES;
    Log(@"Keychain API returned OSStatus %d", (int)status);
    if (outError)
        *outError = [NSError errorWithDomain: NSOSStatusErrorDomain code: status userInfo: nil];
    return NO;
}


@end
