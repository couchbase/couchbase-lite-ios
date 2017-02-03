//
//  CBLQueryRow.mm
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/2/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLQueryRow.h"
#import "CBLQuery+Internal.h"
#import "CBLInternal.h"
#import "CBLCoreBridge.h"
#import "CBLStringBytes.h"
#import "CBLJSON.h"
#import "c4Document.h"
#import "c4DBQuery.h"
#import "Fleece.h"


@implementation CBLQueryRow
{
    @protected
    CBLQueryEnumerator *_enum;
    C4SliceResult _customColumnsData;
    FLArray _customColumns;
}

@synthesize documentID=_documentID, sequence=_sequence;


- (instancetype) initWithEnumerator: (CBLQueryEnumerator*)enumerator
                       c4Enumerator: (C4QueryEnumerator*)e {
    self = [super init];
    if (self) {
        _enum = enumerator;
        _documentID = slice2string(e->docID);
        _sequence = e->docSequence;
        _customColumnsData = c4queryenum_customColumns(e);
        if (_customColumnsData.buf)
            _customColumns = FLValue_AsArray(FLValue_FromTrustedData({_customColumnsData.buf,
                                                                      _customColumnsData.size}));
    }
    return self;
}


- (void) dealloc {
    c4slice_free(_customColumnsData);
}


- (NSString*) description {
    return [NSString stringWithFormat: @"%@[docID='%@']", self.class, _documentID];
}


- (CBLDocument*) document {
    return [_enum.database documentWithID: _documentID];
}


- (NSUInteger) valueCount {
    return FLArray_Count(_customColumns);
}

- (id) valueAtIndex: (NSUInteger)index {
    return FLValue_GetNSObject(FLArray_Get(_customColumns, (uint32_t)index), nullptr, nil);
}

- (bool) booleanAtIndex: (NSUInteger)index {
    return FLValue_AsBool(FLArray_Get(_customColumns, (uint32_t)index));
}

- (NSInteger) integerAtIndex: (NSUInteger)index {
    return (NSInteger)FLValue_AsInt(FLArray_Get(_customColumns, (uint32_t)index));
}

- (float) floatAtIndex: (NSUInteger)index {
    return FLValue_AsFloat(FLArray_Get(_customColumns, (uint32_t)index));
}

- (double) doubleAtIndex: (NSUInteger)index {
    return FLValue_AsDouble(FLArray_Get(_customColumns, (uint32_t)index));
}

- (NSString*) stringAtIndex: (NSUInteger)index {
    id value = [self valueAtIndex: index];
    return [value isKindOfClass: [NSString class]] ? value : nil;
}

- (NSDate*) dateAtIndex: (NSUInteger)index {
    return [CBLJSON dateWithJSONObject: [self valueAtIndex: index]];
}

- (nullable id) objectForSubscript: (NSUInteger)subscript {
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
