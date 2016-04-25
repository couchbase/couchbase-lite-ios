//
//  CBLForestBridge.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 5/1/14.
//  Copyright (c) 2014-2015 Couchbase, Inc. All rights reserved.
//

extern "C" {
#import "c4Database.h"
#import "c4Document.h"
#import "c4DocEnumerator.h"
#import "c4View.h"
#import "c4Key.h"
#import "CBLInternal.h"
}
@class CBLSymmetricKey, CBL_RevID;


namespace CBL {

static inline C4Slice data2slice(UU NSData* data) {
    return (C4Slice){data.bytes, data.length};
}

C4Slice string2slice(UU NSString* str);
NSString* slice2string(C4Slice s);
NSData* slice2data(C4Slice s);
NSData* slice2dataAdopt(C4Slice s);
NSData* slice2dataNoCopy(C4Slice s);
CBL_RevID* slice2revID(C4Slice s);
C4Slice revID2slice(CBL_RevID*);
id slice2jsonObject(C4Slice, CBLJSONReadingOptions);

static inline NSMutableDictionary* slice2mutableDict(C4Slice s) {
    return slice2jsonObject(s, CBLJSONReadingMutableContainers | CBLJSONReadingAllowFragments);
}

C4Slice id2JSONSlice(id obj);

C4Key* id2key(id obj);
id key2id(C4KeyReader kr);

static inline C4GeoArea geoRect2Area(CBLGeoRect rect) {
    return (C4GeoArea){rect.min.x, rect.min.y, rect.max.x, rect.max.y};
}

static inline CBLGeoRect area2GeoRect(C4GeoArea area) {
    return (CBLGeoRect){{area.xmin, area.ymin}, {area.xmax, area.ymax}};
}

C4EncryptionKey symmetricKey2Forest(CBLSymmetricKey* key);


CBLStatus err2status(C4Error);
BOOL err2OutNSError(C4Error, NSError**);    // always returns NO, for convenience


#define CLEANUP(TYPE) __attribute__((cleanup(cleanup_##TYPE))) TYPE
static inline void cleanup_C4SliceResult(C4SliceResult *sp)         { c4slice_free(*sp); }
static inline void cleanup_C4Document(C4Document **docp)            { c4doc_free(*docp); }
static inline void cleanup_C4RawDocument(C4RawDocument **docp)      { c4raw_free(*docp); }
static inline void cleanup_C4DocEnumerator(C4DocEnumerator **ep)    { c4enum_free(*ep); }
static inline void cleanup_C4Key(C4Key **kp)                        { c4key_free(*kp); }
static inline void cleanup_C4KeyValueList(C4KeyValueList **kp)      { c4kv_free(*kp); }
static inline void cleanup_C4QueryEnumerator(C4QueryEnumerator **q) { c4queryenum_free(*q); }
static inline void cleanup_C4Indexer(C4Indexer **ip) {
    if (*ip) c4indexer_end(*ip, false, NULL);
}

} // end namespace CBL

using namespace CBL;


@interface CBLForestBridge : NSObject

+ (CBL_MutableRevision*) revisionObjectFromForestDocInfo: (C4DocumentInfo&)docInfo
                                                  status: (CBLStatus*)outStatus;

+ (CBL_MutableRevision*) revisionObjectFromForestDoc: (C4Document*)doc
                                               docID: (NSString*)docIDIfKnown
                                               revID: (CBL_RevID*)revIDIfKnown
                                            withBody: (BOOL)withBody
                                              status: (CBLStatus*)outStatus;

+ (NSMutableDictionary*) bodyOfSelectedRevision: (C4Document*)doc;

/** Stores the body of a revision (including metadata) into a CBL_MutableRevision. */
+ (CBLStatus) loadBodyOfRevisionObject: (CBL_MutableRevision*)rev
                  fromSelectedRevision: (C4Document*)doc;

@end
