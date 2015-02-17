//
//  CBLQueryRow.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/11/15.
//  Copyright (c) 2012-2015 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBLQuery.h"
#import "CouchbaseLitePrivate.h"
#import "CBLView+Internal.h"


static id fromJSON( NSData* json ) {
    if (!json)
        return nil;
    return [CBLJSON JSONObjectWithData: json
                               options: CBLJSONReadingAllowFragments
                                 error: NULL];
}


@implementation CBLQueryRow
{
    id _key, _value;            // Usually starts as JSON NSData; parsed on demand
    __weak id _parsedKey, _parsedValue;
    UInt64 _sequence;
    NSString* _sourceDocID;
    NSDictionary* _documentProperties;
    CBLDatabase* _database;
    __weak id<CBL_QueryRowStorage> _storage;
}


@synthesize documentProperties=_documentProperties, sourceDocumentID=_sourceDocID,
            database=_database, storage=_storage, sequenceNumber=_sequence;


- (instancetype) initWithDocID: (NSString*)docID
                      sequence: (SequenceNumber)sequence
                           key: (id)key
                         value: (id)value
                 docProperties: (NSDictionary*)docProperties
                       storage: (id<CBL_QueryRowStorage>)storage
{
    self = [super init];
    if (self) {
        // Don't initialize _database yet. I might be instantiated on a background thread (if the
        // query is async) which has a different CBLDatabase instance than the original caller.
        // Instead, the database property will be filled in when I'm added to a CBLQueryEnumerator.
        _sourceDocID = [docID copy];
        _sequence = sequence;
        _key = [key copy];
        _value = [value copy];
        _documentProperties = [docProperties copy];
        _storage = storage;
    }
    return self;
}


- (void) _clearDatabase {
    _database = nil;
}


- (void) moveToView: (CBLView*)view {
    _database = view.database;
    _storage = [view.storage storageForQueryRow: self];
}


- (BOOL) isNonMagicValue {
    return _value && !( [_value isKindOfClass: [NSData class]]
                        && [_storage rowValueIsEntireDoc: _value] );
}


// This is used implicitly by -[CBLLiveQuery update] to decide whether the query result has changed
// enough to notify the client. So it's important that it not give false positives, else the app
// won't get notified of changes.
- (BOOL) isEqual:(id)object {
    if (object == self)
        return YES;
    if (![object isKindOfClass: [CBLQueryRow class]])
        return NO;
    CBLQueryRow* other = object;
    if (_database == other->_database
            && $equal(_key, other->_key)
            && $equal(_sourceDocID, other->_sourceDocID)
            && $equal(_documentProperties, other->_documentProperties)) {
        // If values were emitted, compare them. Otherwise we have nothing to go on so check
        // if _anything_ about the doc has changed (i.e. the sequences are different.)
        if ([self isNonMagicValue] || [other isNonMagicValue])
            return $equal(_value, other->_value);
        else
            return _sequence == other->_sequence;
    }
    return NO;
}


- (id) key {
    id key = _parsedKey;
    if (!key) {
        key = _key;
        if ([key isKindOfClass: [NSData class]]) {  // _key may start out as unparsed JSON data
            key = fromJSON(_key);
            _parsedKey = key;
        }
    }
    return key;
}

- (id) value {
    id value = _parsedValue;
    if (!value) {
        value = _value;
        if ([value isKindOfClass: [NSData class]]) {
            // _value may start out as unparsed Collatable data
            id<CBL_QueryRowStorage> storage = _storage;
            Assert(storage);
            if ([storage rowValueIsEntireDoc: _value]) {
                // Value is a placeholder ("*") denoting that the map function emitted "doc" as
                // the value. So load the body of the revision now:
                Assert(_sequence);
                CBLStatus status;
                value = [storage documentPropertiesWithID: _sourceDocID
                                                 sequence: _sequence
                                                   status: &status];
                if (!value)
                    Warn(@"%@: Couldn't load doc for row value: status %d", self, status);
            } else {
                value = [storage parseRowValue: _value];
            }
            _parsedValue = value;
        }
    }
    return value;
}


- (NSString*) documentID {
    // _documentProperties may have been 'redirected' from a different document
    return _documentProperties.cbl_id ?: _sourceDocID;
}


- (NSString*) documentRevisionID {
    // Get the revision id from either the embedded document contents,
    // or the '_rev' or 'rev' value key:
    NSString* rev = _documentProperties.cbl_rev;
    if (!rev) {
        NSDictionary* value = $castIf(NSDictionary, self.value);
        rev = value.cbl_rev;
        if (value && !rev)
            rev = value[@"rev"];
    }
    return $castIf(NSString, rev);
}


// Custom key & value indexing properties. These are used by the extended "key[0]" / "value[2]"
// key-path syntax (see keyPathForQueryRow(), below.) They're also useful when creating Cocoa
// bindings to query rows, on Mac OS X.

- (id) keyAtIndex: (NSUInteger)index {
    id key = self.key;
    if ([key isKindOfClass:[NSArray class]])
        return (index < [key count]) ? key[index] : nil;
    else
        return (index == 0) ? key : nil;
}

- (id) key0                         {return [self keyAtIndex: 0];}
- (id) key1                         {return [self keyAtIndex: 1];}
- (id) key2                         {return [self keyAtIndex: 2];}
- (id) key3                         {return [self keyAtIndex: 3];}

- (id) valueAtIndex: (NSUInteger)index {
    id value = self.value;
    if ([value isKindOfClass:[NSArray class]])
        return (index < [value count]) ? value[index] : nil;
    else
        return (index == 0) ? value : nil;
}

- (id) value0                         {return [self valueAtIndex: 0];}
- (id) value1                         {return [self valueAtIndex: 1];}
- (id) value2                         {return [self valueAtIndex: 2];}
- (id) value3                         {return [self valueAtIndex: 3];}


- (CBLDocument*) document {
    NSString* docID = self.documentID;
    if (!docID)
        return nil;
    CBLDocument* doc = [_database documentWithID: docID];
    [doc loadCurrentRevisionFrom: self];
    return doc;
}


- (NSArray*) conflictingRevisions {
    // The "_conflicts" value property is added when the query's allDocsMode==kCBLShowConflicts;
    // see -[CBLDatabase getAllDocs:] in CBLDatabase+Internal.m.
    CBLDocument* doc = [_database documentWithID: self.sourceDocumentID];
    NSDictionary* value = $castIf(NSDictionary, self.value);
    NSArray* conflicts = $castIf(NSArray, value[@"_conflicts"]);
    return [conflicts my_map: ^id(id obj) {
        NSString* revID = $castIf(NSString, obj);
        return revID ? [doc revisionWithID: revID] : nil;
    }];
}


// This is used by the router
- (NSDictionary*) asJSONDictionary {
    if (_value || _sourceDocID) {
        return $dict({@"key", self.key},
                     {@"value", self.value},
                     {@"id", _sourceDocID},
                     {@"doc", _documentProperties});
    } else {
        return $dict({@"key", self.key}, {@"error", @"not_found"});
    }

}


- (NSString*) description {
    NSString* valueStr = @"nil";
    if (self.value)
        valueStr = [CBLJSON stringWithJSONObject: self.value
                                         options: CBLJSONWritingAllowFragments error: nil];
    return [NSString stringWithFormat: @"%@[key=%@; value=%@; id=%@]",
            [self class],
            [CBLJSON stringWithJSONObject: self.key options: CBLJSONWritingAllowFragments error: nil],
            valueStr,
            self.documentID];
}


@end



// Tweaks a key-path for use with a CBLQueryRow. The "key" and "value" properties can be
// indexed as arrays using a syntax like "key[0]". (Yes, this is a hack.)
NSString* CBLKeyPathForQueryRow(NSString* keyPath) {
    NSRange bracket = [keyPath rangeOfString: @"["];
    if (bracket.length == 0)
        return keyPath;
    if (![keyPath hasPrefix: @"key["] && ![keyPath hasPrefix: @"value["])
        return nil;
    NSUInteger indexPos = NSMaxRange(bracket);
    if (keyPath.length < indexPos+2 || [keyPath characterAtIndex: indexPos+1] != ']')
        return nil;
    unichar ch = [keyPath characterAtIndex: indexPos];
    if (!isdigit(ch))
        return nil;
    // Delete the brackets, e.g. turning "value[1]" into "value1". CBLQueryRow
    // just so happens to have custom properties key0..key3 and value0..value3.
    NSMutableString* newKey = [keyPath mutableCopy];
    [newKey deleteCharactersInRange: NSMakeRange(indexPos+1, 1)]; // delete ']'
    [newKey deleteCharactersInRange: NSMakeRange(indexPos-1, 1)]; // delete '['
    return newKey;
}
