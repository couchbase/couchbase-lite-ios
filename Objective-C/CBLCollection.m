//
//  CBLCollection.m
//  CouchbaseLite
//
//  Copyright (c) 2022 Couchbase, Inc All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "CBLCollection.h"
#import "CBLIndexable.h"
#import "CBLChangeListenerToken.h"
#import "CBLDatabaseChangeObservable.h"

NSString* const kCBLDefaultCollectionName = @"_default";

@implementation CBLCollection

@synthesize count=_count, name=_name, scope=_scope;

- (instancetype) initWithName: (NSString*)name
                        scope: (nullable CBLScope*)scope
                        error: (NSError**)error {
    CBLAssertNotNil(name);
    
    self = [super init];
    if (self) {
        _name = name;
        if (scope)
            _scope = scope;
    }
    return self;
}

- (BOOL) createIndexWithName: (NSString*)name
                      config: (CBLIndexConfiguration *)config
                       error: (NSError**)error {
    // TODO: add implementation
    return NO;
}

- (BOOL) deleteIndexWithName: (NSString*)name
                       error: (NSError**)error {
    // TODO: add implementation
    return NO;
}

- (NSArray *) indexes {
    // TODO: add implementation
    return [NSArray array];
}

- (id<CBLListenerToken>) addDocumentChangeListenerWithID: (NSString*)listenerID
                                                listener: (void (^)(CBLDocumentChange*))listener {
    // TODO: add the implementation, returning a token to avoid the warning
    id token = [[CBLChangeListenerToken alloc] initWithListener: listener
                                                          queue: nil];
    return token;
}

- (id<CBLListenerToken>) addDocumentChangeListenerWithID: (NSString*)listenerID
                                                   queue: (dispatch_queue_t)queue
                                                listener: (void (^)(CBLDocumentChange*))listener {
    // TODO: add the implementation, returning a token to avoid the warning
    id token = [[CBLChangeListenerToken alloc] initWithListener: listener
                                                          queue: nil];
    return token;
}

- (BOOL) deleteDocument: (CBLDocument*)document
     concurrencyControl: (CBLConcurrencyControl)concurrencyControl
                  error: (NSError**)error {
    // TODO: add implementation
    return NO;
}

- (BOOL) deleteDocument: (CBLDocument*)document
                  error: (NSError**)error {
    // TODO: add implementation
    return NO;
}

- (CBLDocument*) documentWithID: (NSString*)docID {
    // TODO: add implementation
    return nil;
}

- (NSDate*) getDocumentExpirationWithID: (NSString*)docID {
    // TODO: add implementation
    return nil;
}

- (BOOL) purgeDocument: (CBLDocument*)document
                 error: (NSError**)error {
    // TODO: add implementation
    return NO;
}

- (BOOL) purgeDocumentWithID: (NSString*)documentID
                       error: (NSError**)error {
    // TODO: add implementation
    return NO;
}

- (BOOL) saveDocument: (CBLMutableDocument*)document
   concurrencyControl: (CBLConcurrencyControl)concurrencyControl
                error: (NSError**)error {
    // TODO: add implementation
    return NO;
}

- (BOOL) saveDocument: (CBLMutableDocument*)document
      conflictHandler: (BOOL (^)(CBLMutableDocument*, CBLDocument *))conflictHandler
                error: (NSError**)error {
    // TODO: add implementation
    return NO;
}

- (BOOL) saveDocument: (CBLMutableDocument*)document
                error: (NSError**)error {
    // TODO: add implementation
    return NO;
}

- (BOOL) setDocumentExpirationWithID: (NSString*)documentID
                          expiration: (NSDate*)date
                               error: (NSError**)error {
    // TODO: add implementation
    return NO;
}

- (id<CBLListenerToken>) addChangeListener: (void (^)(CBLDatabaseChange*))listener {
    id token = [[CBLChangeListenerToken alloc] initWithListener: listener
                                                          queue: nil];
    return token;
}

- (id<CBLListenerToken>) addChangeListenerWithQueue: (nullable dispatch_queue_t)queue
                                           listener: (void (^)(CBLDatabaseChange*))listener {
    id token = [[CBLChangeListenerToken alloc] initWithListener: listener
                                                          queue: nil];
    return token;
}

@end
