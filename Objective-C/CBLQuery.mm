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
#import "c4Document.h"
#import "c4DBQuery.h"
#import "Fleece.h"
#import "MYErrorUtils.h"


template <typename T>
static inline T* _Nonnull  assertNonNull(T* _Nullable t) {
    NSCAssert(t != nil, @"Unexpected nil value");
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
                            error: (NSError**)outError
{
    self = [super init];
    if (self) {
        NSData* jsonData = [[self class] encodeQuery: where
                                             orderBy: sortDescriptors
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
            NSAssert(NO, @"Invalid specification for CBLQuery");
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
        NSMutableArray* sorts = [NSMutableArray new];
        for (id sd in sortDescriptors) {
            id key;
            if ([sd isKindOfClass: [NSString class]]) {
                if ([sd hasPrefix: @"-"])
                    key = @[@"DESC", [sd substringFromIndex: 1]];
                else
                    key = sd;
            } else {
                NSSortDescriptor* sort = sd;
                key = sort.key;
                if (!sort.ascending)
                    key = @[@"DESC", key];
            }
            [sorts addObject: key];
        }
        q[@"ORDER BY"] = sorts;
    }

    return [NSJSONSerialization dataWithJSONObject: q options: 0 error: outError];
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
    }
    return self;
}


- (CBLDocument*) document {
    return assertNonNull( [_query.database documentWithID: _documentID] );
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
    NSParameterAssert(matchNumber < _matchCount);
    return _matches[matchNumber].termIndex;
}

- (NSRange) textRangeOfMatch: (NSUInteger)matchNumber {
    NSParameterAssert(matchNumber < _matchCount);
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
