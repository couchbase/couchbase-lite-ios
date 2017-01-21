//
//  CBLInternal.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 1/3/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#pragma once
#import "c4.h"
#import "Fleece.h"
#import "CBLDatabase.h"
#import "CBLDocument.h"

NS_ASSUME_NONNULL_BEGIN

/// CBLDatabase:

@interface CBLDatabase ()

@property (readonly, nonatomic, nullable) C4Database* c4db;
@property (readonly, nonatomic) NSString* path;     // For unit tests

- (void) document: (CBLDocument*)doc hasUnsavedChanges: (bool)unsaved;

@end

/// CBLProperties:

@interface CBLProperties ()

// Having changes flag
@property (nonatomic) BOOL hasChanges;

// Set the root or the original properties. After calling this method, the current changes will
// be on top of the new root properties and the hasChanges flag will be reset.
- (void) setRootDict: (nullable FLDict)root orProperties: (nullable NSDictionary*) props;

// Reset both current changes and hasChanges flag.
- (void) resetChanges;

// Subclass should implement this to provide the sharedKeys.
- (FLSharedKeys) sharedKeys;

@end

/// CBLDocument:

@interface CBLDocument ()

- (instancetype) initWithDatabase: (CBLDatabase*)db
                            docID: (NSString*)docID
                        mustExist: (BOOL)mustExist
                            error: (NSError**)outError;

- (void)changedExternally;

@end


NS_ASSUME_NONNULL_END
