//
//  CBLQueryRow.mm
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
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

#import "CBLQueryRow.h"
#import "CBLQueryEnumerator.h"

#import "CBLCoreBridge.h"
#import "CBLData.h"
#import "CBLDatabase+Internal.h"
#import "CBLJSON.h"
#import "CBLPredicateQuery+Internal.h"

#import "c4Document.h"
#import "c4Query.h"
#import "fleece/Fleece.h"

using namespace cbl;


@implementation CBLQueryRow
{
    @protected
    CBLQueryEnumerator *_enum;
    FLArrayIterator _columns;
    bool _current;
}


- (instancetype) initWithEnumerator: (CBLQueryEnumerator*)enumerator
                       c4Enumerator: (C4QueryEnumerator*)e
{
    self = [super init];
    if (self) {
        _enum = enumerator;
        _columns = e->columns;
        _current = true;
    }
    return self;
}


#if 0 //TEMP
- (BOOL) isEqual: (id)other {
    CBLQueryRow *otherRow = $cast(CBLQueryRow, other);
    if (!otherRow)
        return NO;
    return _enum == otherRow->_enum;
}
#endif


- (NSUInteger) valueCount {
    return c4query_columnCount(_enum.c4Query);
}


- (void) stopBeingCurrent {
    _current = false;
}

- (FLValue) flValueAtIndex: (NSUInteger)index {
    if (!_current)
        [NSException raise: NSInternalInconsistencyException
                    format: @"You cannot access a CBLQueryRow value after the enumerator has "
         "advanced past that row"];
    return FLArrayIterator_GetValueAt(&_columns, (uint32_t)index);
}

- (id) valueAtIndex: (NSUInteger)index {
    return FLValue_GetNSObject([self flValueAtIndex: index], nil);
}

- (bool) booleanAtIndex: (NSUInteger)index {
    return FLValue_AsBool([self flValueAtIndex: index]);
}

- (NSInteger) integerAtIndex: (NSUInteger)index {
    return (NSInteger)FLValue_AsInt([self flValueAtIndex: index]);
}

- (float) floatAtIndex: (NSUInteger)index {
    return FLValue_AsFloat([self flValueAtIndex: index]);
}

- (double) doubleAtIndex: (NSUInteger)index {
    return FLValue_AsDouble([self flValueAtIndex: index]);
}

- (NSString*) stringAtIndex: (NSUInteger)index {
    return asString([self valueAtIndex: index]);
}

- (NSDate*) dateAtIndex: (NSUInteger)index {
    return asDate([self valueAtIndex: index]);
}

- (nullable id) objectAtIndexedSubscript: (NSUInteger)subscript {
    return [self valueAtIndex: subscript];
}


@end



@implementation CBLFullTextQueryRow
{
    C4FullTextMatch* _matches;
}

@synthesize matchCount=_matchCount;


- (instancetype) initWithEnumerator: (CBLQueryEnumerator*)enumerator
                       c4Enumerator: (C4QueryEnumerator*)e
{
    self = [super initWithEnumerator: enumerator c4Enumerator: e];
    if (self) {
        _matchCount = e->fullTextMatchCount;
        if (_matchCount > 0) {
            _matches = new C4FullTextMatch[_matchCount];
            memcpy(_matches, e->fullTextMatches, _matchCount * sizeof(C4FullTextMatch));
        }
    }
    return self;
}


- (void) dealloc {
    delete [] _matches;
}


- (NSData*) fullTextUTF8Data {
    return sliceResult2data(c4query_fullTextMatched(_enum.c4Query, _matches, nullptr));
}


- (NSString*) fullTextMatched {
    NSData* data = self.fullTextUTF8Data;
    return data ? [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding] : nil;
}


- (NSUInteger) termIndexOfMatch: (NSUInteger)matchNumber {
    Assert(matchNumber < _matchCount);
    return _matches[matchNumber].term;
}

- (NSRange) textRangeOfMatch: (NSUInteger)matchNumber {
    Assert(matchNumber < _matchCount);
    NSUInteger byteStart  = _matches[matchNumber].start;
    NSUInteger byteLength = _matches[matchNumber].length;
    NSData* rawText = self.fullTextUTF8Data;
    if (!rawText)
        return NSMakeRange(NSNotFound, 0);
    return NSMakeRange(charCountOfUTF8ByteRange(rawText.bytes, 0, byteStart),
                       charCountOfUTF8ByteRange(rawText.bytes, byteStart, byteStart + byteLength));
}


// Determines the number of NSString (UTF-16) characters in a byte range of a UTF-8 string. */
static NSUInteger charCountOfUTF8ByteRange(const void* bytes, NSUInteger byteStart, NSUInteger byteEnd) {
    if (byteStart == byteEnd)
        return 0;
    NSString* prefix = [[NSString alloc] initWithBytesNoCopy: (UInt8*)bytes + byteStart
                                                      length: byteEnd - byteStart
                                                    encoding: NSUTF8StringEncoding
                                                freeWhenDone: NO];
    return prefix.length;
}


@end
