//
//  CBL_RevID.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 4/18/16.
//  Copyright © 2016 Couchbase, Inc. All rights reserved.
//

#import "CBL_RevID.h"
#import "CBL_Revision.h"
#import "CBLMisc.h"

#ifdef GNUSTEP
#import <openssl/sha.h>
#else
#define COMMON_DIGEST_FOR_OPENSSL
#import <CommonCrypto/CommonDigest.h>
#endif


static unsigned parseDigits(const char* str, const char* end);


@implementation CBL_RevID

+ (instancetype) fromString: (NSString*)str {
    return [self fromData: [str dataUsingEncoding: NSUTF8StringEncoding]];
}

+ (instancetype) fromData: (NSData*)data {
    return [[CBL_TreeRevID alloc] initWithData: data];
}

- (NSString*) description {
    return self.asString;
}

- (BOOL) isEqual:(id)object {
#if DEBUG
    Assert(!object || [object isKindOfClass: [CBL_RevID class]]);
#endif
    return [object isKindOfClass: [CBL_RevID class]] && [self.asData isEqual: [object asData]];
}

- (NSUInteger) hash {
    return self.asData.hash;
}

- (id) copyWithZone: (NSZone*)zone {
    return self;
}

- (NSString*) asString {
    return [[NSString alloc] initWithData: self.asData encoding: NSASCIIStringEncoding];
}

- (NSData*) asData {
    AssertAbstractMethod();
}

- (unsigned) generation {
    return 0;
}

- (NSString*) suffix {
    return nil;
}

- (NSComparisonResult) compare: (CBL_RevID*)other {
    AssertAbstractMethod();
}

@end



@implementation NSString (CBL_RevID)

- (CBL_RevID*) cbl_asRevID {
    return [CBL_RevID fromString: self];
}

@end


@implementation NSArray (CBL_RevID)

- (NSArray<CBL_RevID*>*) cbl_asRevIDs {
    return [self my_map: ^id(NSString* str) {
        return [CBL_RevID fromString: str];
    }];
}

- (NSArray<CBL_RevID*>*) cbl_asMaybeRevIDs {
    return [self my_map: ^id(NSString* str) {
        if (![str isKindOfClass: [NSString class]])
            return nil;
        return [CBL_RevID fromString: str];
    }];
}

@end



@implementation CBL_TreeRevID
{
    NSData* _data;
}

- (instancetype) initWithData: (NSData*)data {
    self = [super init];
    if (self) {
        _data = [data copy];
    }
    return self;
}

- (NSData*) asData {
    return _data;
}

- (unsigned) generation {
    const char* start = _data.bytes;
    const char* dash = memchr(start, '-', _data.length);
    if (!dash || dash-start > 9)
        return 0;
    return parseDigits(start, dash);
}

- (NSString*) suffix {
    size_t length = _data.length;
    const char* start = _data.bytes;
    const char* dash = memchr(start, '-', length);
    if (!dash)
        return nil;
    length -= (dash+1 - start);
    if (length == 0)
        return nil;
    return [[NSString alloc] initWithBytes: dash+1 length: length encoding: NSASCIIStringEncoding];
}

- (NSComparisonResult) compare: (CBL_RevID*)other {
    CBL_TreeRevID* otherTree = $cast(CBL_TreeRevID, other);     // assertion failure if $cast fails!
    return CBLCollateRevIDs(NULL,
                            (int)_data.length, _data.bytes,
                            (int)otherTree->_data.length, otherTree->_data.bytes);
}

/** Given an existing revision ID, generates an ID for the next revision.
    Returns nil if prevID is invalid. */
+ (CBL_RevID*) revIDForJSON: (NSData*)json
                    deleted: (BOOL)deleted
                  prevRevID: (CBL_RevID*)prevID
{
    // Revision IDs have a generation count, a hyphen, and a hex digest.
    unsigned generation = 0;
    if (prevID) {
        generation = prevID.generation;
        if (generation == 0)
            return nil;
    }

    // Generate a digest for this revision based on the previous revision ID, document JSON,
    // and attachment digests. This doesn't need to be secure; we just need to ensure that this
    // code consistently generates the same ID given equivalent revisions.
    __block MD5_CTX ctx;
    unsigned char digestBytes[MD5_DIGEST_LENGTH];
    MD5_Init(&ctx);

    if (prevID) {
        // (Note: It's not really correct to skip this entirely if prevID is nil -- we should be
        // writing the 0 length byte -- but it's necessary for consistency with prior versions,
        // which had a bug in CBLWithStringBytes that didn't call the block if the string was nil.)
        __block BOOL tooLong = NO;
        NSData* prevIDData = prevID.asData;
        size_t length = prevIDData.length;
        if (length > 0xFF)
            tooLong = YES;
        uint8_t lengthByte = length & 0xFF;
        MD5_Update(&ctx, &lengthByte, 1);       // prefix with length byte
        if (length > 0)
            MD5_Update(&ctx, prevIDData.bytes, length);
    }

    uint8_t deletedByte = deleted != NO;
    MD5_Update(&ctx, &deletedByte, 1);

    MD5_Update(&ctx, json.bytes, json.length);
    MD5_Final(digestBytes, &ctx);

    char hex[11 + 2*MD5_DIGEST_LENGTH + 1];
    char *dst = hex + CBLAppendDecimal(hex, generation+1);
    *dst++ = '-';
    dst = CBLAppendHex(dst, digestBytes, sizeof(digestBytes));
    return [CBL_RevID fromData: [NSData dataWithBytes: hex length: dst - hex]];
}


+ (NSDictionary*) makeRevisionHistoryDict: (NSArray<CBL_RevID*>*)history {
    AssertContainsRevIDs(history);
    if (!history)
        return nil;

    // Try to extract descending numeric prefixes:
    NSMutableArray* suffixes = $marray();
    id start = nil;
    int lastRevNo = -1;
    for (CBL_RevID* revID in history) {
        unsigned revNo = revID.generation;
        NSString* suffix = revID.suffix;
        if (revNo > 0 && suffix) {
            if (!start)
                start = @(revNo);
            else if ((int)revNo != lastRevNo - 1) {
                start = nil;
                break;
            }
            lastRevNo = revNo;
            [suffixes addObject: suffix];
        } else {
            start = nil;
            break;
        }
    }

    if (start)
        return $dict({@"ids", suffixes}, {@"start", start});
    else
        return $dict({@"ids", [history my_map: ^(CBL_RevID* rev) {return rev.asString;}]});
}


+ (NSArray<CBL_RevID*>*) parseRevisionHistoryDict: (NSDictionary*)dict {
    if (!dict)
        return nil;
    // Extract the history, expanding the numeric prefixes:
    __block int start = [$castIf(NSNumber, dict[@"start"]) intValue];
    NSArray* revIDs = $castIf(NSArray, dict[@"ids"]);
    return [revIDs my_map: ^id(NSString* revIDStr) {
        if (![revIDStr isKindOfClass: [NSString class]])
            return nil;
        if (start)
            revIDStr = $sprintf(@"%d-%@", start--, revIDStr);
        return revIDStr.cbl_asRevID;
    }];
}



@end



#pragma mark - COLLATE REVISION IDS:


static inline int sgn(int n) {
    return n>0 ? 1 : (n<0 ? -1 : 0);
}

static int defaultCollate(const char* str1, int len1, const char* str2, int len2) {
    int result = memcmp(str1, str2, MIN(len1, len2));
    return sgn(result ?: (len1 - len2));
}

static unsigned parseDigits(const char* str, const char* end) {
    unsigned result = 0;
    for (; str < end; ++str) {
        if (!isdigit(*str))
            return 0;
        result = 10*result + digittoint(*str);
    }
    return result;
}

/* A proper revision ID consists of a generation number, a hyphen, and an arbitrary suffix.
   Compare the generation numbers numerically, and then the suffixes lexicographically.
   If either string isn't a proper rev ID, fall back to lexicographic comparison. */
int CBLCollateRevIDs(void *context,
                    int len1, const void * chars1,
                    int len2, const void * chars2)
{
    const char *rev1 = chars1, *rev2 = chars2;
    const char* dash1 = memchr(rev1, '-', len1);
    const char* dash2 = memchr(rev2, '-', len2);
    if ((dash1==rev1+1 && dash2==rev2+1)
            || dash1 > rev1+8 || dash2 > rev2+8
            || dash1==NULL || dash2==NULL)
    {
        // Single-digit generation #s, or improper rev IDs; just compare as plain text:
        return defaultCollate(rev1,len1, rev2,len2);
    }
    // Parse generation numbers. If either is invalid, revert to default collation:
    int gen1 = parseDigits(rev1, dash1);
    int gen2 = parseDigits(rev2, dash2);
    if (!gen1 || !gen2)
        return defaultCollate(rev1,len1, rev2,len2);
    
    // Compare generation numbers; if they match, compare suffixes:
    return sgn(gen1 - gen2) ?: defaultCollate(dash1+1, len1-(int)(dash1+1-rev1),
                                              dash2+1, len2-(int)(dash2+1-rev2));
}
