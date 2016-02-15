//
//  CBLView.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/19/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CouchbaseLitePrivate.h"
#import "CBL_ViewStorage.h"
#import "CBLView+Internal.h"
#import "CBLSpecialKey.h"
#import "CBL_Shared.h"
#import "CBLInternal.h"
#import "CBJSONEncoder.h"
#import "CBLMisc.h"
#import "ExceptionUtils.h"


DefineLogDomain(View);


NSString* const kCBLViewChangeNotification = @"CBLViewChange";


// GROUP_VIEWS_BY_DEFAULT alters the behavior of -viewsInGroup and thus which views will be
// re-indexed together. If it's defined, all views with no "/" in the name are treated as a single
// group and will be re-indexed together. If it's not defined, such views aren't in any group
// and will be re-indexed only individually. (The latter matches the CBL 1.0 behavior and
// avoids unexpected slowdowns if an app suddenly has all its views re-index at once.)
#undef GROUP_VIEWS_BY_DEFAULT


@implementation CBLQueryOptions

@synthesize startKey, endKey, startKeyDocID, endKeyDocID, keys, filter, fullTextQuery;

- (instancetype)init {
    self = [super init];
    if (self) {
        limit = kCBLQueryOptionsDefaultLimit;
        inclusiveStart = YES;
        inclusiveEnd = YES;
        fullTextRanking = YES;
        // everything else will default to nil/0/NO
    }
    return self;
}

- (BOOL) isEmpty {
    return limit == 0 || (keys && keys.count == 0);
}

- (id) minKey {
    return descending ? endKey : startKey;
}

- (id) maxKey {
    return CBLKeyForPrefixMatch(descending ? startKey : endKey, prefixMatchLevel);
}

@end



#pragma mark -

@implementation CBLView


- (instancetype) initWithDatabase: (CBLDatabase*)db name: (NSString*)name create: (BOOL)create {
    Assert(db);
    Assert(name.length);
    self = [super init];
    if (self) {
        _storage = [db.storage viewStorageNamed: name create: create];
        if (!_storage)
            return nil;
        _storage.delegate = self;
        _weakDB = db;
        _name = [name copy];
    }
    return self;
}


@synthesize name=_name, storage=_storage;


- (NSString*) description {
    return [NSString stringWithFormat: @"%@[%@/%@]", self.class, _weakDB.name, _name];
}



#if DEBUG
- (void) setCollation: (CBLViewCollation)collation {
    _collation = collation;
}

// for unit tests only
- (void) forgetMapBlock {
    CBLDatabase* db = _weakDB;
    CBL_Shared* shared = db.shared;
    [shared setValue: nil
             forType: @"map" name: _name inDatabaseNamed: db.name];
    [shared setValue: nil
             forType: @"reduce" name: _name inDatabaseNamed: db.name];
}
#endif


- (CBLDatabase*) database {
    return _weakDB;
}


- (void) close {
    [_storage close];
    _storage = nil;
    _weakDB = nil;
}


- (void) deleteIndex {
    [_storage deleteIndex];
}


- (void) deleteView {
    [_storage deleteView];
    [_weakDB forgetViewNamed: _name];
    [self close];
}


#pragma mark - CONFIGURATION:


- (CBLMapBlock) registeredMapBlock {
    CBLDatabase* db = _weakDB;
    return [db.shared valueForType: @"map" name: _name inDatabaseNamed: db.name];
}

- (CBLMapBlock) mapBlock {
    CBLMapBlock map = self.registeredMapBlock;
    if (!map)
        if ([self compileFromDesignDoc] == kCBLStatusOK)
            map = self.registeredMapBlock;
    return map;
}

- (CBLReduceBlock) reduceBlock {
    CBLDatabase* db = _weakDB;
    return [db.shared valueForType: @"reduce" name: _name inDatabaseNamed: db.name];
}

- (NSString*) mapVersion {
    CBLDatabase* db = _weakDB;
    return [db.shared valueForType: @"mapVersion" name: _name inDatabaseNamed: db.name];
}

- (BOOL) setMapBlock: (CBLMapBlock)mapBlock
         reduceBlock: (CBLReduceBlock)reduceBlock
             version: (NSString *)version
{
    Assert(mapBlock);
    Assert(version);

    BOOL changed = ![version isEqualToString: self.mapVersion];

    CBLDatabase* db = _weakDB;
    CBL_Shared* shared = db.shared;
    [shared setValue: [mapBlock copy]
             forType: @"map" name: _name inDatabaseNamed: db.name];
    [shared setValue: version
             forType: @"mapVersion" name: _name inDatabaseNamed: db.name];
    [shared setValue: [reduceBlock copy]
             forType: @"reduce" name: _name inDatabaseNamed: db.name];
    if (changed) {
        [_storage setVersion: version];
        // update any live queries that might be listening to this view, now that it has changed
        [self postPublicChangeNotification];
    }
    return changed;
}


- (BOOL) setMapBlock: (CBLMapBlock)mapBlock version: (NSString *)version {
    return [self setMapBlock: mapBlock reduceBlock: nil version: version];
}


- (NSString*) documentType {
    CBLDatabase* db = _weakDB;
    return [db.shared valueForType: @"docType" name: _name inDatabaseNamed: db.name];
}

- (void) setDocumentType: (NSString*)type {
    CBLDatabase* db = _weakDB;
    [db.shared setValue: type forType: @"docType" name: _name inDatabaseNamed: db.name];
}


#pragma mark - COMPILATION:


static id<CBLViewCompiler> sCompiler;


+ (void) setCompiler: (id<CBLViewCompiler>)compiler {
    sCompiler = compiler;
}

+ (id<CBLViewCompiler>) compiler {
    return sCompiler;
}


- (CBLStatus) compileFromDesignDoc {
    if (self.registeredMapBlock != nil)
        return kCBLStatusOK;

    // see if there's a design doc with a CouchDB-style view definition we can compile:
    NSString* language;
    NSDictionary* viewProps = $castIf(NSDictionary, [_weakDB getDesignDocFunction: self.name
                                                                              key: @"views"
                                                                         language: &language]);
    if (!viewProps)
        return kCBLStatusNotFound;
    LogTo(View, @"%@: Attempting to compile %@ from design doc", self.name, language);
    if (![CBLView compiler])
        return kCBLStatusNotImplemented;
    return [self compileFromProperties: viewProps language: language];
}


- (CBLStatus) compileFromProperties: (NSDictionary*)viewProps language: (NSString*)language {
    if (!language)
        language = @"javascript";
    NSString* mapSource = viewProps[@"map"];
    if (!mapSource)
        return kCBLStatusNotFound;
    CBLMapBlock mapBlock = [[CBLView compiler] compileMapFunction: mapSource language: language];
    if (!mapBlock) {
        Warn(@"View %@ could not compile %@ map fn: %@", _name, language, mapSource);
        return kCBLStatusCallbackError;
    }
    NSString* reduceSource = viewProps[@"reduce"];
    CBLReduceBlock reduceBlock = NULL;
    if (reduceSource) {
        reduceBlock = [[CBLView compiler] compileReduceFunction: reduceSource language: language];
        if (!reduceBlock) {
            Warn(@"View %@ could not compile %@ map fn: %@", _name, language, reduceSource);
            return kCBLStatusCallbackError;
        }
    }

    // Version string is based on a digest of the properties:
    NSError* error;
    NSString* version = CBLHexSHA1Digest([CBJSONEncoder canonicalEncoding: viewProps error: &error]);
    [self setMapBlock: mapBlock reduceBlock: reduceBlock version: version];

    self.documentType = $castIf(NSString, viewProps[@"documentType"]);
    NSDictionary* options = $castIf(NSDictionary, viewProps[@"options"]);
    _collation = ($equal(options[@"collation"], @"raw")) ? kCBLViewCollationRaw
                                                         : kCBLViewCollationUnicode;
    return kCBLStatusOK;
}


#pragma mark - INDEXING:


- (NSArray*) viewsInGroup {
    int (^filter)(CBLView* view);
    NSRange slash = [_name rangeOfString: @"/"];
    if (slash.length > 0) {
        // Return all the views whose name starts with the same prefix before the slash:
        NSString* prefix = [_name substringToIndex: NSMaxRange(slash)];
        filter = ^int(CBLView* view) {
            return [view.name hasPrefix: prefix];
        };
    } else {
#ifdef GROUP_VIEWS_BY_DEFAULT
        // Return all the views that don't have a slash in their names:
        filter = ^int(CBLView* view) {
            return [view.name rangeOfString: @"/"].length == 0;
        };
#else
        // Without GROUP_VIEWS_BY_DEFAULT, views with no "/" in the name aren't in any group:
        return @[self];
#endif
    }
    return [_weakDB.allViews my_filter: filter];
}


/** Updates the view's index, if necessary. (If nothing changed, returns kCBLStatusNotModified.)*/
- (CBLStatus) _updateIndex {
    return [self updateIndexes: self.viewsInGroup];
}

- (void) updateIndex {
    CBLStatus status = [self updateIndexes: self.viewsInGroup];
    if (CBLStatusIsError(status))
        Warn(@"Error %d updating index of %@", status, self);
}

- (void) updateIndexAsync: (void (^)())onComplete {
    CBLDatabase* db = self.database;
    [db.manager backgroundTellDatabaseNamed: db.name to: ^(CBLDatabase *bgdb)
     {
         CBLView* bgview = [bgdb existingViewNamed: self.name];
         [bgview updateIndex];
         [db doAsync: ^{
             onComplete();
         }];
     }];
}

- (CBLStatus) updateIndexAlone {
    return [self updateIndexes: @[self]];
}

- (CBLStatus) updateIndexes: (NSArray*)views {
    NSArray* storages = [views my_map:^id(CBLView* view) {
        return view.storage;
    }];
    return [_storage updateIndexes: storages];
}

- (void) postPublicChangeNotification {
    // Post the public kCBLViewChangeNotification:
    NSNotification* notification = [NSNotification notificationWithName: kCBLViewChangeNotification
                                                                 object: self
                                                               userInfo: nil];
    [_weakDB postNotification:notification];
}

+ (NSNumber*) totalValues: (NSArray*)values {
    double total = 0;
    for (NSNumber* value in values)
        total += value.doubleValue;
    return @(total);
}


#pragma mark - QUERYING:


- (NSUInteger) currentTotalRows {
    return _storage.totalRows;
}


- (NSUInteger) totalRows {
    [self updateIndex];
    return [self currentTotalRows];
}


- (SequenceNumber) lastSequenceIndexed {
    return _storage.lastSequenceIndexed;
}


- (SequenceNumber) lastSequenceChangedAt {
    return _storage.lastSequenceChangedAt;
}


- (BOOL) stale {
    return self.lastSequenceIndexed < _weakDB.lastSequenceNumber;
}


- (CBLQuery*) createQuery {
    return [[CBLQuery alloc] initWithDatabase: self.database view: self];
}


/** Main internal call to query a view. */
- (CBLQueryEnumerator*) _queryWithOptions: (CBLQueryOptions*)options
                                   status: (CBLStatus*)outStatus
{
    if (!options)
        options = [CBLQueryOptions new];
    else if (options.isEmpty)
        return [[CBLQueryEnumerator alloc] initWithDatabase: self.database
                                                       view: self
                                             sequenceNumber: self.lastSequenceIndexed
                                                       rows: nil];

    CBLQueryEnumerator* e = [_storage queryWithOptions: options status: outStatus];
    [e setDatabase: self.database view: self];
    if (e)
        LogTo(Query, @"Query %@: Returning iterator", _name);
    else
        LogTo(Query, @"Query %@: Failed with status %d", _name, *outStatus);
    return e;
}


@end
