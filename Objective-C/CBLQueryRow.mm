//
//  CBLQueryRow.mm
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/2/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLQueryRow.h"
#import "CBLQueryEnumerator.h"
#import "CBLPredicateQuery+Internal.h"
#import "CBLInternal.h"
#import "CBLCoreBridge.h"
#import "CBLStringBytes.h"
#import "CBLJSON.h"
#import "c4Document.h"
#import "c4Query.h"
#import "Fleece.h"


@implementation CBLQueryRow
{
    @protected
    CBLQueryEnumerator *_enum;
    FLArrayIterator _columns;
    bool _current;
}

@synthesize documentID=_documentID, sequence=_sequence;


- (instancetype) initWithEnumerator: (CBLQueryEnumerator*)enumerator
                       c4Enumerator: (C4QueryEnumerator*)e
{
    self = [super init];
    if (self) {
        _enum = enumerator;
        _documentID = slice2string(e->docID);
        _sequence = e->docSequence;
        _columns = e->columns;
        _current = true;
    }
    return self;
}


- (NSString*) description {
    return [NSString stringWithFormat: @"%@[docID='%@']", self.class, _documentID];
}


#if 0 //TEMP
- (BOOL) isEqual: (id)other {
    CBLQueryRow *otherRow = $cast(CBLQueryRow, other);
    if (!otherRow)
        return NO;
    return _enum == otherRow->_enum;
}
#endif


- (CBLDocument*) document {
    return _documentID ? [_enum.database documentWithID: _documentID] : nil;
}


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
    return FLValue_GetNSObject([self flValueAtIndex: index], nullptr, nil);
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
    return $castIf(NSString, [self valueAtIndex: index]);
}

- (NSDate*) dateAtIndex: (NSUInteger)index {
    return [CBLJSON dateWithJSONObject: [self valueAtIndex: index]];
}

- (nullable id) objectAtIndexedSubscript: (NSUInteger)subscript {
    return [self valueAtIndex: subscript];
}


@end




@implementation CBLFullTextQueryRow
{
    C4FullTextTerm* _matches;
}

@synthesize matchCount=_matchCount;


- (instancetype) initWithEnumerator: (CBLQueryEnumerator*)enumerator
                       c4Enumerator: (C4QueryEnumerator*)e
{
    self = [super initWithEnumerator: enumerator c4Enumerator: e];
    if (self) {
        _matchCount = e->fullTextTermCount;
        if (_matchCount > 0) {
            _matches = new C4FullTextTerm[_matchCount];
            memcpy(_matches, e->fullTextTerms, _matchCount * sizeof(C4FullTextTerm));
        }
    }
    return self;
}


- (void) dealloc {
    delete [] _matches;
}


- (NSData*) fullTextUTF8Data {
    CBLStringBytes docIDSlice(self.documentID);
    return sliceResult2data(c4query_fullTextMatched(_enum.c4Query, docIDSlice,
                                                    self.sequence, nullptr));
}


- (NSString*) fullTextMatched {
    NSData* data = self.fullTextUTF8Data;
    return data ? [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding] : nil;
}


- (NSUInteger) termIndexOfMatch: (NSUInteger)matchNumber {
    Assert(matchNumber < _matchCount);
    return _matches[matchNumber].termIndex;
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
