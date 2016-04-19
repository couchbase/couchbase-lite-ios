//
//  CBLChangeMatcher.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/8/15.
//  Copyright (c) 2014-2015 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBLChangeMatcher.h"
#import "CBL_RevID.h"


@interface CBLRevInfoMatcher : CBLJSONDictMatcher
@end

@implementation CBLRevInfoMatcher
{
    NSMutableArray<CBL_RevID*>* _revIDs;
}

- (id)initWithArray: (NSMutableArray<CBL_RevID*>*)revIDs
{
    self = [super init];
    if (self) {
        _revIDs = revIDs;
    }
    return self;
}

- (bool) matchValue:(id)value forKey:(NSString *)key {
    if ([key isEqualToString: @"rev"]) {
        CBL_RevID* revID = $castIf(NSString, value).cbl_asRevID;
        if (!revID)
            return false;
        [_revIDs addObject: revID];
    }
    return true;
}

@end



@implementation CBLChangeMatcher
{
    id _sequence;
    NSString* _docID;
    NSMutableArray<CBL_RevID*>* _revs;
    bool _deleted;
    CBLTemplateMatcher* _revsMatcher;
    CBLChangeMatcherClient _client;
}

+ (CBLJSONMatcher*) changesFeedMatcherWithClient: (CBLChangeMatcherClient)client
                               expectWrapperDict: (BOOL)expectWrapperDict
{
    CBLChangeMatcher* changeMatcher = [[CBLChangeMatcher alloc] initWithClient: client];
    id template = @[changeMatcher];
    if (expectWrapperDict)
        template = @{@"results": template};
    return [[CBLTemplateMatcher alloc] initWithTemplate: @[template]];
}

- (id) initWithClient: (CBLChangeMatcherClient)client {
    self = [super init];
    if (self) {
        _client = client;
        _revs = $marray();
        CBLRevInfoMatcher* m = [[CBLRevInfoMatcher alloc] initWithArray: _revs];
        _revsMatcher = [[CBLTemplateMatcher alloc] initWithTemplate: @[m]];
    }
    return self;
}

- (bool) matchValue:(id)value forKey:(NSString *)key {
    if ([key isEqualToString: @"deleted"])
        _deleted = [value boolValue];
    else if ([key isEqualToString: @"seq"])
        _sequence = value;
    else if ([self.key isEqualToString: @"id"])
        _docID = value;
    return true;
}

- (CBLJSONArrayMatcher*) startArray {
    if ([self.key isEqualToString: @"changes"])
        return (CBLJSONArrayMatcher*)_revsMatcher;
    return [super startArray];
}

- (id) end {
    //Log(@"Ended ChangeMatcher with seq=%@, id='%@', deleted=%d, revs=%@", _sequence, _docID, _deleted, _revs);
    if (!_sequence || !_docID)
        return nil;
    _client(_sequence, _docID, [_revs copy], _deleted);
    _sequence = nil;
    _docID = nil;
    _deleted = false;
    [_revs removeAllObjects];
    return self;
}

@end
