//
//  CBLCollator.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/8/11.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.
//
//  http://wiki.apache.org/couchdb/View_collation#Collation_Specification

#import "CBLCollateJSON.h"


#if 0 // Set to 1 for code-coverage testing
#define ifc(TEST) if (Cover(TEST))
#else
#define ifc if
#endif


static inline int cmp(int n1, int n2) {
    return (n1>n2) ? 1 : ((n1<n2)? -1 : 0);
}

static inline int dcmp(double n1, double n2) {
    return (n1>n2) ? 1 : ((n1<n2)? -1 : 0);
}


// Maps an ASCII character to its relative priority in the Unicode collation sequence.
static uint8_t kCharPriority[128];
// Same thing but case-insensitive.
static uint8_t kCharPriorityCaseInsensitive[128];

static void initializeCharPriorityMap(void) {
    static const char* const kInverseMap = "\t\n\r `^_-,;:!?.'\"()[]{}@*/\\&#%+<=>|~$0123456789aAbBcCdDeEfFgGhHiIjJkKlLmMnNoOpPqQrRsStTuUvVwWxXyYzZ";
    uint8_t priority = 1;
    for (unsigned i=0; i<strlen(kInverseMap); i++)
        kCharPriority[(uint8_t)kInverseMap[i]] = priority++;

    // This table gives lowercase letters the same priority as uppercase:
    memcpy(kCharPriorityCaseInsensitive, kCharPriority, sizeof(kCharPriority));
    for (uint8_t c = 'a'; c <= 'z'; c++)
        kCharPriorityCaseInsensitive[c] = kCharPriority[toupper(c)];
}


// Types of values, ordered according to CouchDB collation order (see view_collation.js tests)
typedef enum {
    kEndArray,
    kEndObject,
    kComma,
    kColon,
    kNull,
    kFalse,
    kTrue,
    kNumber,
    kString,
    kArray,
    kObject,
    kIllegal
} ValueType;


// "Raw" ordering is: 0:number, 1:false, 2:null, 3:true, 4:object, 5:array, 6:string
// (according to view_collation_raw.js)
static SInt8 kRawOrderOfValueType[] = {
    -4, -3, -2, -1,
    2, 1, 3, 0, 6, 5, 4,
    7
};


static uint8_t kTypeOf[256];

static void initializeValueTypes(void) {
    memset(&kTypeOf, kIllegal, sizeof(kTypeOf));
    memset(&kTypeOf['0'], kNumber, 10);
    kTypeOf['n'] = kNull;
    kTypeOf['f'] = kFalse;
    kTypeOf['t'] = kTrue;
    kTypeOf['-'] = kNumber;
    kTypeOf['"'] = kString;
    kTypeOf[']'] = kEndArray;
    kTypeOf['}'] = kEndObject;
    kTypeOf[','] = kComma;
    kTypeOf[':'] = kColon;
    kTypeOf['['] = kArray;
    kTypeOf['{'] = kObject;
}


static ValueType valueTypeOf(char c) {
    ValueType v = kTypeOf[(uint8_t)c];
#if DEBUG
    if (v == kIllegal)
        Warn(@"Unexpected character '%c' parsing JSON", c);
#endif
    return v;
}


static char convertEscape(const char **in) {
    char c = *++(*in);
    switch (c) {
        case 'u': {
            // \u is a Unicode escape; 4 hex digits follow.
            const char* digits = *in + 1;
            *in += 4;
            int uc = (digittoint(digits[0]) << 12) | (digittoint(digits[1]) << 8) |
                     (digittoint(digits[2]) <<  4) | (digittoint(digits[3]));
            if (uc > 127)
                return 0xFF;        // This function doesn't support non-ASCII characters
            return (char)uc;
        }
        case 'b':   return '\b';
        case 'n':   return '\n';
        case 'r':   return '\r';
        case 't':   return '\t';
        default:    return c;
    }
}


static int compareStringsASCII(const char** in1, const char** in2) {
    const char* str1 = *in1, *str2 = *in2;
    while(true) {
        char c1 = *++str1;
        char c2 = *++str2;

        // If one string ends, the other is greater; if both end, they're equal:
        ifc (c1 == '"') {
            ifc (c2 == '"')
                break;
            else
                return -1;
        } else ifc (c2 == '"')
            return 1;
        
        // Handle escape sequences:
        ifc (c1 == '\\')
            c1 = convertEscape(&str1);
        ifc (c2 == '\\')
            c2 = convertEscape(&str2);

        if ((c1 & 0x80) || (c2 & 0x80))
            Warn(@"CBLCollateJSON can't compare Unicode chars in ASCII collation");

        // Compare the next characters:
        int s = cmp(c1, c2);
        ifc (s)
            return s;
    }
    
    // Strings are equal, so update the positions:
    *in1 = str1 + 1;
    *in2 = str2 + 1;
    return 0;
}


// Unicode collation, but fails (returns -2) if non-ASCII characters are found.
// Basic rule is to compare case-insensitively, but if the strings compare equal, let the one that's
// higher case-sensitively win (where uppercase is _greater_ than lowercase, unlike in ASCII.)
static int compareStringsUnicodeFast(const char** in1, const char** in2) {
    const char* str1 = *in1, *str2 = *in2;
    int resultIfEqual = 0;
    while(true) {
        char c1 = *++str1;
        char c2 = *++str2;

        // If one string ends, the other is greater; if both end, they're equal:
        ifc (c1 == '"') {
            ifc (c2 == '"')
                break;
            else
                return -1;
        } else ifc (c2 == '"')
            return 1;

        // Handle escape sequences:
        ifc (c1 == '\\')
            c1 = convertEscape(&str1);
        ifc (c2 == '\\')
            c2 = convertEscape(&str2);

        if ((c1 & 0x80) || (c2 & 0x80))
            return -2; // fail: I only handle ASCII

        // Compare the next characters, according to case-insensitive Unicode character priority:
        int s = cmp(kCharPriorityCaseInsensitive[(uint8_t)c1],
                    kCharPriorityCaseInsensitive[(uint8_t)c2]);
        ifc (s)
            return s;

        // Remember case-sensitive result too
        ifc (resultIfEqual == 0 && c1 != c2)
            resultIfEqual = cmp(kCharPriority[(uint8_t)c1], kCharPriority[(uint8_t)c2]);
    }

    ifc (resultIfEqual)
        return resultIfEqual;

    // Strings are equal, so update the positions:
    *in1 = str1 + 1;
    *in2 = str2 + 1;
    return 0;
}


static NSString* createStringFromJSON(const char** in) {
    // Scan the JSON string to find its end and whether it contains escapes:
    const char* start = ++*in;
    unsigned escapes = 0;
    const char* str;
    for (str = start; *str != '"'; ++str) {
        ifc (*str == '\\') {
            ++str;
            ifc (*str == 'u') {
                escapes += 5;  // \uxxxx adds 5 bytes
                str += 4;
            } else
                escapes += 1;
        }
    }
    *in = str + 1;
    size_t length = str - start;
    
    BOOL freeWhenDone = NO;
    ifc (escapes > 0) {
        length -= escapes;
        char* buf = malloc(length);
        char* dst = buf;
        char c;
        for (str = start; (c = *str) != '"'; ++str) {
            ifc (c == '\\')
                c = convertEscape(&str);
            *dst++ = c;
        }
        CAssertEq(dst-buf, (int)length);
        start = buf;
        freeWhenDone = YES;
    }
    
    NSString* nsstr = [[NSString alloc] initWithBytesNoCopy: (void*)start
                                                     length: length
                                                   encoding: NSUTF8StringEncoding
                                               freeWhenDone: freeWhenDone];
    CAssert(nsstr != nil, @"Failed to convert to string: start=%p, length=%u", start, length);
    return nsstr;
}


static int compareStringsUnicode(const char** in1, const char** in2) {
    int result = compareStringsUnicodeFast(in1, in2);
    if (result > -2)
        return result;
    // Fast compare failed, so resort to using NSString:
    @autoreleasepool {
        NSString* str1 = createStringFromJSON(in1);
        NSString* str2 = createStringFromJSON(in2);
        return (int)[str1 localizedCompare: str2];
    }
}


static double readNumber(const char* start, const char* end, char** endOfNumber) {
    CAssert(end > start);
    // First copy the string into a zero-terminated buffer so we can safely call strtod:
    size_t len = end - start;
    char buf[50];
    char* str = (len < sizeof(buf)) ? buf : malloc(len + 1);
    if (!str)
        return 0.0;
    memcpy(str, start, len);
    str[len] = '\0';
    
    char* endInStr;
    double result = strtod(str, &endInStr);
    *endOfNumber = (char*)start + (endInStr - str);
    ifc (str != buf)
        free(str);
    return result;
}


int CBLCollateJSONLimited(void *context,
                         int len1, const void * chars1,
                         int len2, const void * chars2,
                         unsigned arrayLimit)
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        initializeValueTypes();
        initializeCharPriorityMap();
    });

    const char* str1 = chars1;
    const char* str2 = chars2;
    int depth = 0;
    unsigned arrayIndex = 0;
    
    do {
        // Get the types of the next token in each string:
        ValueType type1 = valueTypeOf(*str1);
        ValueType type2 = valueTypeOf(*str2);
        // If types don't match, stop and return their relative ordering:
        if (type1 != type2) {
            ifc (depth == 1 && (type1 == kComma || type2 == kComma)) {
                ifc (++arrayIndex >= arrayLimit)
                    return 0;
            }
            ifc (context != kCBLCollateJSON_Raw)
                return cmp(type1, type2);
            else
                return cmp(kRawOrderOfValueType[type1], kRawOrderOfValueType[type2]);
            
        // If types match, compare the actual token values:
        } else switch (type1) {
            case kNull:
            case kTrue:
                str1 += 4;
                str2 += 4;
                break;
            case kFalse:
                str1 += 5;
                str2 += 5;
                break;
            case kNumber: {
                char* next1, *next2;
                int diff;
                ifc (depth == 0) {
                    // At depth 0, be careful not to fall off the end of the input, because there
                    // won't be any delimiters (']' or '}') after the number!
                    diff = dcmp( readNumber(str1, chars1 + len1, &next1),
                                 readNumber(str2, chars2 + len2, &next2) );
                } else {
                    diff = dcmp( strtod(str1, &next1), strtod(str2, &next2) );
                }
                if (diff)
                    return diff;    // Numbers don't match
                str1 = next1;
                str2 = next2;
                break;
            }
            case kString: {
                int diff;
                ifc (context == kCBLCollateJSON_Unicode)
                    diff = compareStringsUnicode(&str1, &str2);
                else
                    diff = compareStringsASCII(&str1, &str2);
                if (diff)
                    return diff;    // Strings don't match
                break;
            }
            case kArray:
            case kObject:
                ++str1;
                ++str2;
                ++depth;
                break;
            case kEndArray:
            case kEndObject:
                ++str1;
                ++str2;
                --depth;
                break;
            case kComma:
                ifc (depth == 1 && (++arrayIndex >= arrayLimit))
                    return 0;
                // else fall through:
            case kColon:
                ++str1;
                ++str2;
                break;
            case kIllegal:
                return 0;
        }
    } while (depth > 0);    // Keep going as long as we're inside an array or object
    return 0;
}


int CBLCollateJSON(void *context,
                  int len1, const void * chars1,
                  int len2, const void * chars2)
{
    return CBLCollateJSONLimited(context, len1, chars1, len2, chars2, UINT_MAX);
}
