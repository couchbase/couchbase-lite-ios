//
//  CBLQuery.mm
//  Couchbase Lite
//
//  Created by Jens Alfke on 11/30/16.
//  Copyright © 2016 Couchbase. All rights reserved.
//

#import "CBLQuery.h"
#import "CBLQuery+Internal.h"
#import "CBLInternal.h"
#import "CBLCoreBridge.h"
#import "CBLStringBytes.h"
#import "CBLJSON.h"
#import "c4Document.h"
#import "c4DBQuery.h"
#import "Fleece.h"
extern "C" {
    #import "MYErrorUtils.h"
    #import "Test.h"
}


#define kBadQuerySpecError -1
#define CBLErrorDomain @"CouchbaseLite"
#define mkError(ERR, FMT, ...)  MYReturnError(ERR, kBadQuerySpecError, CBLErrorDomain, \
                                              FMT, ## __VA_ARGS__)

template <typename T>
static inline T* _Nonnull  assertNonNull(T* _Nullable t) {
    Assert(t != nil, @"Unexpected nil value");
    return (T*)t;
}


@interface CBLQuery ()
@property (readonly, nonatomic) C4Query* c4query;
@end

@interface CBLQueryRow ()
- (instancetype) initWithQuery: (CBLQuery*)query enumerator: (C4QueryEnumerator*)e;
@end

@interface CBLQueryEnumerator : NSEnumerator
- (instancetype) initWithQuery: (CBLQuery*)query enumerator: (C4QueryEnumerator*)e;
@end




@implementation CBLQuery

@synthesize database=_db, skip=_skip, limit=_limit, parameters=_parameters, c4query=_c4Query;


C4LogDomain QueryLog;

+ (void) initialize {
    if (self == [CBLQuery class]) {
        QueryLog = c4log_getDomain("Query", true);
    }
}


- (instancetype) initWithDatabase: (CBLDatabase*)db
                            where: (id)where
                          orderBy: (nullable NSArray*)sortDescriptors
                        returning: (nullable NSArray*)returning
                            error: (NSError**)outError
{
    self = [super init];
    if (self) {
        NSData* jsonData = [[self class] encodeQuery: where
                                             orderBy: sortDescriptors
                                           returning: returning
                                               error: outError];
        if (!jsonData)
            return nil;
        C4LogToAt(QueryLog, kC4LogInfo,
                  "Query encoded as %.*s", (int)jsonData.length, (char*)jsonData.bytes);
        C4Error c4Err;
        _db = db;
        _c4Query = c4query_new(db.c4db, {jsonData.bytes, jsonData.length}, &c4Err);
        if (!_c4Query) {
            convertError(c4Err, outError);
            return nil;
        }
        _limit = NSUIntegerMax;
    }
    return self;
}


+ (NSData*) encodeQuery: (id)where
                orderBy: (nullable NSArray*)sortDescriptors
              returning: (nullable NSArray*)returning
                  error: (NSError**)outError
{
    id whereJSON = nil;
    if (where) {
        if ([where isKindOfClass: [NSArray class]] || [where isKindOfClass: [NSDictionary class]]) {
            whereJSON = where;
        } else if ([where isKindOfClass: [NSPredicate class]]) {
            whereJSON = [self encodePredicate: where error: outError];
        } else if ([where isKindOfClass: [NSString class]]) {
            where = [NSPredicate predicateWithFormat: (NSString*)where argumentArray: nil];
            whereJSON = [self encodePredicate: where error: outError];
        } else if (where != nil) {
            Assert(NO, @"Invalid specification for CBLQuery");
        }
        if (!whereJSON)
            return nil;
    }

    NSMutableDictionary* q;
    if ([whereJSON isKindOfClass: [NSDictionary class]]) {
        q = [whereJSON mutableCopy];
    } else {
        q = [NSMutableDictionary new];
        if (whereJSON)
            q[@"WHERE"] = whereJSON;
    }

    if (sortDescriptors) {
        NSArray* sorts = [self encodeSortDescriptors: sortDescriptors error: outError];
        if (!sorts)
            return nil;
        q[@"ORDER BY"] = sorts;
    }

    if (returning) {
        NSArray* select = [self encodeExpressions: returning error: outError];
        if (!select)
            return nil;
        q[@"WHAT"] = select;
    }

    return [NSJSONSerialization dataWithJSONObject: q options: 0 error: outError];
}


+ (NSArray*) encodeSortDescriptors: (NSArray*)sortDescriptors error: (NSError**)outError {
    NSMutableArray* sorts = [NSMutableArray new];
    for (id sd in sortDescriptors) {
        NSString* keyStr;
        bool descending = false;
        // Each item of sortDescriptors can be an NSString or NSSortDescriptor:
        if ([sd isKindOfClass: [NSString class]]) {
            descending = [sd hasPrefix: @"-"];
            keyStr = descending ? [sd substringFromIndex: 1] : sd;
        } else {
            Assert([sd isKindOfClass: [NSSortDescriptor class]]);
            descending = ![sd ascending];
            keyStr = [sd key];
        }

        // Convert to JSON as a rank() call or a key-path:
        id key;
        if ([keyStr hasPrefix: @"rank("]) {
            if (![keyStr hasSuffix: @")"])
                return mkError(outError, @"Invalid rank sort descriptor"), nil;
            keyStr = [keyStr substringWithRange: {5, [keyStr length] - 6}];
            NSExpression* expr = [NSExpression expressionWithFormat: keyStr argumentArray: @[]];
            key = [self encodeExpression: expr error: outError];
            if (!key)
                return nil;
        } else {
            key = @[ [@"." stringByAppendingString: keyStr] ];
        }
        
        if (descending)
            key = @[@"DESC", key];
        [sorts addObject: key];
    }
    return sorts;
}


- (void) dealloc {
    c4query_free(_c4Query);
}


- (NSEnumerator<CBLQueryRow*>*) run: (NSError**)outError {
    C4QueryOptions options = kC4DefaultQueryOptions;
    options.skip = _skip;
    options.limit = _limit;
    NSData* paramJSON = nil;
    if (_parameters) {
        paramJSON = [NSJSONSerialization dataWithJSONObject: _parameters
                                                    options: 0
                                                      error: outError];
        if (!paramJSON)
            return nil;
    }
    C4Error c4Err;
    auto e = c4query_run(_c4Query, &options, {paramJSON.bytes, paramJSON.length}, &c4Err);
    if (!e) {
        C4LogToAt(QueryLog, kC4LogError, "CBLQuery failed: %d/%d", c4Err.domain, c4Err.code);
        convertError(c4Err, outError);
        return nil;
    }
    return [[CBLQueryEnumerator alloc] initWithQuery: self enumerator: e];
}

@end




@implementation CBLQueryEnumerator
{
    CBLQuery *_query;
    C4QueryEnumerator* _c4enum;
    C4Error _error;
}


- (instancetype) initWithQuery: (CBLQuery*)query enumerator: (C4QueryEnumerator*)e
{
    self = [super init];
    if (self) {
        _query = query;
        _c4enum = e;
        C4LogToAt(QueryLog, kC4LogInfo, "Beginning query enumeration (%p)", _c4enum);
    }
    return self;
}


- (void) dealloc {
    c4queryenum_free(_c4enum);
}


- (CBLQueryRow*) nextObject {
    if (c4queryenum_next(_c4enum, &_error)) {
        Class c = _c4enum->fullTextTermCount ? [CBLFullTextQueryRow class] : [CBLQueryRow class];
        return [[c alloc] initWithQuery: _query enumerator: _c4enum];
    } else if (_error.code) {
        C4LogToAt(QueryLog, kC4LogError, "CBLQueryEnumerator error: %d/%d",
                  _error.domain, _error.code);
        return nil;
    } else {
        C4LogToAt(QueryLog, kC4LogInfo, "End of query enumeration (%p)", _c4enum);
        return nil;
    }
}


//???: Should we make this public? How else can the app find the error?
- (NSError*) error {
    if (_error.code == 0)
        return nil;
    NSError* error;
    convertError(_error, &error);
    return error;
}


@end




@implementation CBLQueryRow
{
    @protected
    CBLQuery *_query;
    C4SliceResult _customColumnsData;
    FLArray _customColumns;
}

@synthesize documentID=_documentID, sequence=_sequence;


- (instancetype) initWithQuery: (CBLQuery*)query enumerator: (C4QueryEnumerator*)e {
    self = [super init];
    if (self) {
        _query = query;
        _documentID = assertNonNull( [[NSString alloc] initWithBytes: e->docID.buf
                                                              length: e->docID.size
                                                            encoding: NSUTF8StringEncoding] );
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
    return assertNonNull( [_query.database documentWithID: _documentID] );
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
    return FLValue_AsInt(FLArray_Get(_customColumns, (uint32_t)index));
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


- (instancetype) initWithQuery: (CBLQuery*)query enumerator: (C4QueryEnumerator*)e {
    self = [super initWithQuery: query enumerator: e];
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
    C4SliceResult text = c4query_fullTextMatched(_query.c4query, docIDSlice, self.sequence, nullptr);
    if (!text.buf)
        return nil;
    NSData *result = [NSData dataWithBytes: text.buf length: text.size];
    c4slice_free(text);
    return result;
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
