//
//  CBLDocumentInfo.m
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

#import "CBLDocumentInfo.h"
#import "CBLDocument+Internal.h"
#import "CBLFleece.hh"
#import "CBLData.h"

using namespace fleece;

@implementation CBLDocumentInfo {
    CBLDictionary* _dict;
    fleece::MDict<id> _mDict;
}

@synthesize  id=_id, revisionID=_revisionID;

- (instancetype) initWithID: (NSString*)docID revID: (NSString*)revID body: (FLSlice)body {
    self = [super init];
    if (self) {
        _id = docID;
        _revisionID = revID;
        
        FLValue docBodyVal = FLValue_FromData(body, kFLTrusted);
        FLDict dict = FLValue_AsDict(docBodyVal);
        
        
        FLDictIterator iter;
        FLDictIterator_Begin(dict, &iter);
        FLValue value;
        while (NULL != (value = FLDictIterator_GetValue(&iter))) {
            id val = FLValue_GetNSObject(value, nil);
            _mDict.set(FLDictIterator_GetKeyString(&iter), [val cbl_toCBLObject]);
            FLDictIterator_Next(&iter);
        }
        
        _dict = [[CBLDictionary alloc] initWithCopyOfMDict: _mDict isMutable: false];
    }
    return self;
}

#pragma mark - CBLDictionary

- (NSUInteger) count {
    return _dict.count;
}

- (NSArray*) keys {
    return _dict.keys;
}

- (nullable id) valueForKey: (nonnull NSString*)key {
    return [_dict valueForKey: key];
}

- (nullable NSString*) stringForKey: (nonnull NSString*)key {
    return [_dict stringForKey: key];
}

- (nullable NSNumber*) numberForKey: (nonnull NSString*)key {
    return [_dict numberForKey: key];
}

- (NSInteger) integerForKey:(nonnull NSString*)key {
    return [_dict integerForKey: key];
}

- (long long) longLongForKey: (nonnull NSString*)key {
    return [_dict longLongForKey: key];
}

- (float) floatForKey: (nonnull NSString*)key {
    return [_dict floatForKey: key];
}

- (double) doubleForKey: (nonnull NSString*)key {
    return [_dict doubleForKey: key];
}

- (BOOL) booleanForKey: (nonnull NSString*)key {
    return [_dict booleanForKey: key];
}

- (nullable NSDate*) dateForKey: (nonnull NSString*)key {
    return [_dict dateForKey: key];
}

- (nullable CBLBlob*) blobForKey: (nonnull NSString*)key {
    return [_dict blobForKey: key];
}

- (nullable CBLArray*) arrayForKey: (nonnull NSString*)key {
    return [_dict arrayForKey: key];
}

- (nullable CBLDictionary*) dictionaryForKey:(nonnull NSString*)key {
    return [_dict dictionaryForKey: key];
}

- (BOOL) containsValueForKey: (nonnull NSString *)key {
    return [_dict booleanForKey: key];
}

- (CBLFragment *) objectForKeyedSubscript: (NSString *)key {
    return [_dict objectForKeyedSubscript: key];
}

- (NSUInteger) countByEnumeratingWithState: (nonnull NSFastEnumerationState*)state
                                   objects: (id  _Nullable __unsafe_unretained* _Nonnull)buffer
                                     count: (NSUInteger)len
{
    return [_dict countByEnumeratingWithState: state objects: buffer count: len];
}

- (NSDictionary<NSString *,id>*) toDictionary {
    return [_dict toDictionary];
}

- (NSString*) toJSON {
    return [_dict toJSON];
}

@end
