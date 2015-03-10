//
//  CBLQuery+FullTextSearch.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 9/21/13.
//  Copyright (c) 2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CouchbaseLitePrivate.h"
#import "CBLQuery+FullTextSearch.h"
#import "CBLView+Internal.h"


static NSUInteger utf8BytesToChars(const void* bytes, NSUInteger byteStart, NSUInteger byteEnd);


@implementation CBLQuery (FullTextSearch)

- (NSString*) fullTextQuery                         {return _fullTextQuery;}
- (void) setFullTextQuery:(NSString *)fullTextQuery {_fullTextQuery = [fullTextQuery copy];}
- (BOOL) fullTextSnippets                           {return _fullTextSnippets;}
- (void) setFullTextSnippets:(BOOL)fullTextSnippets {_fullTextSnippets = fullTextSnippets;}
- (BOOL) fullTextRanking                            {return _fullTextRanking;}
- (void) setFullTextRanking:(BOOL)fullTextRanking   {_fullTextRanking = fullTextRanking;}

@end


@implementation CBLFullTextQueryRow
{
    UInt64 _fullTextID;
    NSMutableArray* _matchOffsets;
}


- (instancetype) initWithDocID: (NSString*)docID
                      sequence: (SequenceNumber)sequence
                    fullTextID: (UInt64)fullTextID
                         value: (id)value
                       storage: (id<CBL_QueryRowStorage>)storage
{
    self = [super initWithDocID: docID sequence: sequence key: $null value: value
                  docProperties: nil storage: storage];
    if (self) {
        _fullTextID = fullTextID;
        _matchOffsets = [[NSMutableArray alloc] initWithCapacity: 4];
    }
    return self;
}

- (void) addTerm: (NSUInteger)term atRange: (NSRange)range {
    [_matchOffsets addObject: @"?"]; //FIX
    [_matchOffsets addObject: @(term)];
    [_matchOffsets addObject: @(range.location)];
    [_matchOffsets addObject: @(range.length)];
}

- (NSData*) fullTextUTF8Data {
    return [self.storage fullTextForDocument: self.documentID
                                    sequence: self.sequenceNumber
                                  fullTextID: _fullTextID];
}

- (NSString*) fullText {
    NSData* data = self.fullTextUTF8Data;
    if (!data)
        return nil;
    return [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding];
}

- (NSUInteger) matchCount {
    return _matchOffsets.count / 4;
}

- (NSUInteger) termIndexOfMatch: (NSUInteger)matchNumber {
    return [_matchOffsets[4*matchNumber + 1] unsignedIntegerValue];
}

- (NSRange) textRangeOfMatch: (NSUInteger)matchNumber {
    NSUInteger byteStart  = [_matchOffsets[4*matchNumber + 2] unsignedIntegerValue];
    NSUInteger byteLength = [_matchOffsets[4*matchNumber + 3] unsignedIntegerValue];
    NSData* rawText = self.fullTextUTF8Data;
    return NSMakeRange(utf8BytesToChars(rawText.bytes, 0, byteStart),
                       utf8BytesToChars(rawText.bytes, byteStart, byteStart + byteLength));
}


// Overridden to add FTS result info
- (NSDictionary*) asJSONDictionary {
    NSMutableDictionary* dict = [[super asJSONDictionary] mutableCopy];
    if (!dict[@"error"]) {
        [dict removeObjectForKey: @"key"];
        if (_matchOffsets) {
            NSMutableArray* matches = [[NSMutableArray alloc] init];
            for (NSUInteger i = 0; i < _matchOffsets.count; i += 4) {
                NSRange r = [self textRangeOfMatch: i/4];
                [matches addObject: @{@"term": _matchOffsets[i+1],
                                      @"range": @[@(r.location), @(r.length)]}];
            }
            dict[@"matches"] = matches;
        }
    }
    return dict;
}


@end




// Determine the number of characters in a range of UTF-8 bytes. */
static NSUInteger utf8BytesToChars(const void* bytes, NSUInteger byteStart, NSUInteger byteEnd) {
    if (byteStart == byteEnd)
        return 0;
    NSString* prefix = [[NSString alloc] initWithBytesNoCopy: (UInt8*)bytes + byteStart
                                                      length: byteEnd - byteStart
                                                    encoding: NSUTF8StringEncoding
                                                freeWhenDone: NO];
    return prefix.length;
}
