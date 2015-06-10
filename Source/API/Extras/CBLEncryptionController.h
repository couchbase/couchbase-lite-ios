//
//  CBLEncryptionController.h
//  Couchbase Lite
//
//  Created by Jens Alfke on 2/13/15.
//  Copyright (c) 2015 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLManager, CBLDatabase, UIViewController;


/** A completion routine invoked by -[EncryptionController openDatabaseAsync:].
    @param db  The Couchbase Lite database, or nil if it was not opened.
    @param error  The error, or nil if none. (If db and error are both nil, the user canceled.) */
typedef void(^CBLEncryptionControllerCompletion)(CBLDatabase* db, NSError* error);


/** Creates or opens an encrypted Couchbase Lite database, including all needed user interaction. (Note: database encryption is supported only if you build your app with SQLCipher, instead of
    the system-supplied libSQLite.dylib.)
    Due to the need for user interaction, the API is asynchronous.
    * If the database does not exist, the user will be prompted to make up a password, and the
      database will be created and encrypted with that password.
    * If the database already exists and is not encrypted, it's opened immediately.
    * If the database already exists, and is encrypted, the user will be prompted to enter the
      password. An arbitrary number of retries are allowed, but only at two-second intervals.
    * If the device supports Touch ID, password entry is skipped in favor of storing a
      raw key (256 random bits) in a Keychain entry protected (encrypted) by Touch ID. The user 
      will be prompted to to authenticate via Touch ID when opening the database.
    The password entry UI is localizable (see comments in the source code) but pretty minimal, using
    UIAlertController. It can be replaced entirely by overriding -askForPasswordWithPrompt:. */
@interface CBLEncryptionController : NSObject

/** Returns YES if Touch ID authentication is available on the current device. */
+ (BOOL) isTouchIDAvailable;

/** Creates a controller that will open (or create) a named database.
    @param manager  The CBLManager instance to use.
    @param dbName  The name of the database to open. */
- (instancetype) initWithManager: (CBLManager*)manager
                    databaseName: (NSString*)dbName    NS_DESIGNATED_INITIALIZER;

/** Creates a controller that will open (or create) a named database in the default CBLManager.
    @param dbName  The name of the database to open. */
- (instancetype) initWithDatabaseName: (NSString*)dbName;

- (instancetype) init NS_UNAVAILABLE;

@property (readonly) NSString* databaseName;

/** The UIViewController to present password alerts on top of.
    If this is not set, password-based authentication will fail. */
@property UIViewController* parentController;

/** Should Touch ID authentication be used instead of a user-supplied password?
    Defaults to YES if Touch ID is available, but can be set to NO if you explicitly don't want to
    use it. 
    Setting this property to YES is pointless (it will not cause your iPhone to grow a
    Touch ID sensor!)
    Setting it to NO is discouraged unless you are _very_ paranoid about security. Touch ID
    verification is hackable, but requires specialized techniques like acquiring fingerprints and
    making silicone replicas of them. In practice TouchID is going to provide stronger security
    than the sort of weak passcode a user will end up using on a mobile app. */
@property BOOL useTouchID;

/** Begins the process of opening a database. When the database has been opened, or an error has
    occurred, the completion block will be invoked on the main thread.
    The completion block might be called before this method returns (instead of asynchronously).
    This happens if the database is unencrypted, if the encryption key has already been registered,
    or if the password UI can't be presented because there's no parentController. */
- (void) openDatabaseAsync: (CBLEncryptionControllerCompletion)completion;

@end



/** Modes in which the EncryptionController's password UI is displayed.
    (Not needed by clients, only subclassers who want to replace/alter the UI.) */
typedef enum : uint8_t {
    CBLPasswordPromptEnterPassword,          ///< Initial prompt to enter existing password
    CBLPasswordPromptReEnterPassword,        ///< Password was incorrect; re-enter it
    CBLPasswordPromptCreatePassword,         ///< Initial prompt to create new password
    CBLPasswordPromptCreatePasswordTooShort, ///< New password was too short (< 6 chars)
    CBLPasswordPromptCreatePasswordMismatch, ///< New password didn't match in both textfields
    CBLPasswordPromptTouchID                 ///< Used only by Touch ID UI, not for passwords
} CBLPasswordPrompt;


/** Methods for subclasses to call/override, in order to replace the password UI. */
@interface CBLEncryptionController (Protected)

/** Prompts the user to enter a password; either a new password to protect a database with, or
    the password to open an existing database. Afterwards, it calls -completedWithKey:orError:.
    The default implementation uses UIAlertController; you can override it to present a custom
    UI.
    @param prompt  The type of password entry to prompt for.
    @param outError  On return, set to the error that prevented the UI from being presented.
    @return YES if the UI will be presented, NO if for some reason it can't be presented. */
- (BOOL) askForPasswordWithPrompt: (CBLPasswordPrompt)prompt
                            error: (NSError**)outError;

/** Called after a password has been entered by the user. Should be called from an overridden
    -askForPasswordWithPrompt: method, but you probably don't need to override this
    method itself.
    @param keyOrPassword  The password (as an NSString*) or raw key (as NSData*), or nil if
        password entry failed.
    @param error  The error that caused password entry to fail. As a special case, when both
        keyOrPassword and error are nil, it means that the user canceled. */
- (void) completedWithKey: (id)keyOrPassword orError: (NSError*)error;

@end
