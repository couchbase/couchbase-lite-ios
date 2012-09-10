//
//  TDCollator.m
//  TouchDB
//
//  Created by Jens Alfke on 12/8/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
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

#import "TDCollateJSON.h"


static int cmp(int n1, int n2) {
    int diff = n1 - n2;
    return diff > 0 ? 1 : (diff < 0 ? -1 : 0);
}

static int dcmp(double n1, double n2) {
    double diff = n1 - n2;
    return diff > 0.0 ? 1 : (diff < 0.0 ? -1 : 0);
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


static ValueType valueTypeOf(char c) {
    switch (c) {
        case 'n':           return kNull;
        case 'f':           return kFalse;
        case 't':           return kTrue;
        case '0' ... '9':
        case '-':           return kNumber;
        case '"':           return kString;
        case ']':           return kEndArray;
        case '}':           return kEndObject;
        case ',':           return kComma;
        case ':':           return kColon;
        case '[':           return kArray;
        case '{':           return kObject;
        default:
            Warn(@"Unexpected character '%c' parsing JSON", c);
            return kIllegal;
    }
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
                Warn(@"TDCollateJSON can't correctly compare \\u%.4s", digits);
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
        if (c1 == '"') {
            if (c2 == '"')
                break;
            else
                return -1;
        } else if (c2 == '"')
            return 1;
        
        // Handle escape sequences:
        if (c1 == '\\')
            c1 = convertEscape(&str1);
        if (c2 == '\\')
            c2 = convertEscape(&str2);
        
        // Compare the next characters:
        int s = cmp(c1, c2);
        if (s)
            return s;
    }
    
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
        if (*str == '\\') {
            ++str;
            if (*str == 'u') {
                escapes += 5;  // \uxxxx adds 5 bytes
                str += 4;
            } else
                escapes += 1;
        }
    }
    *in = str + 1;
    size_t length = str - start;
    
    BOOL freeWhenDone = NO;
    if (escapes > 0) {
        length -= escapes;
        char* buf = malloc(length);
        char* dst = buf;
        char c;
        for (str = start; (c = *str) != '"'; ++str) {
            if (c == '\\')
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
    NSString* str1 = createStringFromJSON(in1);
    NSString* str2 = createStringFromJSON(in2);
    int result = (int)[str1 localizedCompare: str2];
    [str1 release];
    [str2 release];
    return result;
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
    if (len >= sizeof(buf))
        free(str);
    return result;
}


int TDCollateJSON(void *context,
               int len1, const void * chars1,
               int len2, const void * chars2)
{
    const char* str1 = chars1;
    const char* str2 = chars2;
    int depth = 0;
    
    do {
        // Get the types of the next token in each string:
        ValueType type1 = valueTypeOf(*str1);
        ValueType type2 = valueTypeOf(*str2);
        // If types don't match, stop and return their relative ordering:
        if (type1 != type2) {
            if (context != kTDCollateJSON_Raw)
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
                if (depth == 0) {
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
                if (context == kTDCollateJSON_Unicode)
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


#pragma mark - UNIT TESTS:


#if DEBUG
// encodes an object to a C string in JSON format. JSON fragments are allowed.
static const char* encode(id obj) {
    NSString* str = [TDJSON stringWithJSONObject: obj
                                         options: TDJSONWritingAllowFragments error: NULL];
    CAssert(str);
    return [str UTF8String];
}

static void testEscape(const char* source, char decoded) {
    const char* pos = source;
    CAssertEq(convertEscape(&pos), decoded);
    CAssertEq((size_t)pos, (size_t)(source + strlen(source) - 1));
}

TestCase(TDCollateConvertEscape) {
    testEscape("\\\\",    '\\');
    testEscape("\\t",     '\t');
    testEscape("\\u0045", 'E');
    testEscape("\\u0001", 1);
    testEscape("\\u0000", 0);
}

static int collate(void *mode, const void * str1, const void * str2) {
    // Be evil and put numeric garbage past the ends of str1 and str2 (see bug #138):
    size_t len1 = strlen(str1), len2 = strlen(str2);
    char buf1[len1 + 3], buf2[len2 + 3];
    strlcpy(buf1, str1, sizeof(buf1));
    strlcat(buf1, "99", sizeof(buf1));
    strlcpy(buf2, str2, sizeof(buf1));
    strlcat(buf2, "88", sizeof(buf1));
    return TDCollateJSON(mode, (int)len1, buf1, (int)len2, buf2);
}

TestCase(TDCollateScalars) {
    RequireTestCase(TDCollateConvertEscape);
    void* mode = kTDCollateJSON_Unicode;
    CAssertEq(collate(mode, "true", "false"), 1);
    CAssertEq(collate(mode, "false", "true"), -1);
    CAssertEq(collate(mode, "null", "17"), -1);
    CAssertEq(collate(mode, "1", "1"), 0);
    CAssertEq(collate(mode, "123", "1"), 1);
    CAssertEq(collate(mode, "123", "0123.0"), 0);
    CAssertEq(collate(mode, "123", "\"123\""), -1);
    CAssertEq(collate(mode, "\"1234\"", "\"123\""), 1);
    CAssertEq(collate(mode, "\"1234\"", "\"1235\""), -1);
    CAssertEq(collate(mode, "\"1234\"", "\"1234\""), 0);
    CAssertEq(collate(mode, "\"12\\/34\"", "\"12/34\""), 0);
    CAssertEq(collate(mode, "\"\\/1234\"", "\"/1234\""), 0);
    CAssertEq(collate(mode, "\"1234\\/\"", "\"1234/\""), 0);
#ifndef GNUSTEP     // FIXME: GNUstep doesn't support Unicode collation yet
    CAssertEq(collate(mode, "\"a\"", "\"A\""), -1);
    CAssertEq(collate(mode, "\"A\"", "\"aa\""), -1);
    CAssertEq(collate(mode, "\"B\"", "\"aa\""), 1);
#endif
}

TestCase(TDCollateASCII) {
    RequireTestCase(TDCollateConvertEscape);
    void* mode = kTDCollateJSON_ASCII;
    CAssertEq(collate(mode, "true", "false"), 1);
    CAssertEq(collate(mode, "false", "true"), -1);
    CAssertEq(collate(mode, "null", "17"), -1);
    CAssertEq(collate(mode, "123", "1"), 1);
    CAssertEq(collate(mode, "123", "0123.0"), 0);
    CAssertEq(collate(mode, "123", "\"123\""), -1);
    CAssertEq(collate(mode, "\"1234\"", "\"123\""), 1);
    CAssertEq(collate(mode, "\"1234\"", "\"1235\""), -1);
    CAssertEq(collate(mode, "\"1234\"", "\"1234\""), 0);
    CAssertEq(collate(mode, "\"12\\/34\"", "\"12/34\""), 0);
    CAssertEq(collate(mode, "\"\\/1234\"", "\"/1234\""), 0);
    CAssertEq(collate(mode, "\"1234\\/\"", "\"1234/\""), 0);
    CAssertEq(collate(mode, "\"A\"", "\"a\""), -1);
    CAssertEq(collate(mode, "\"B\"", "\"a\""), -1);
}

TestCase(TDCollateRaw) {
    void* mode = kTDCollateJSON_Raw;
    CAssertEq(collate(mode, "false", "17"), 1);
    CAssertEq(collate(mode, "false", "true"), -1);
    CAssertEq(collate(mode, "null", "true"), -1);
    CAssertEq(collate(mode, "[\"A\"]", "\"A\""), -1);
    CAssertEq(collate(mode, "\"A\"", "\"a\""), -1);
    CAssertEq(collate(mode, "[\"b\"]", "[\"b\",\"c\",\"a\"]"), -1);
}

TestCase(TDCollateArrays) {
    void* mode = kTDCollateJSON_Unicode;
    CAssertEq(collate(mode, "[]", "\"foo\""), 1);
    CAssertEq(collate(mode, "[]", "[]"), 0);
    CAssertEq(collate(mode, "[true]", "[true]"), 0);
    CAssertEq(collate(mode, "[false]", "[null]"), 1);
    CAssertEq(collate(mode, "[]", "[null]"), -1);
    CAssertEq(collate(mode, "[123]", "[45]"), 1);
    CAssertEq(collate(mode, "[123]", "[45,67]"), 1);
    CAssertEq(collate(mode, "[123.4,\"wow\"]", "[123.40,789]"), 1);
    CAssertEq(collate(mode, "[5,\"wow\"]", "[5,\"wow\"]"), 0);
    CAssertEq(collate(mode, "[5,\"wow\"]", "1"), 1);
    CAssertEq(collate(mode, "1", "[5,\"wow\"]"), -1);
}

TestCase(TDCollateNestedArrays) {
    void* mode = kTDCollateJSON_Unicode;
    CAssertEq(collate(mode, "[[]]", "[]"), 1);
    CAssertEq(collate(mode, "[1,[2,3],4]", "[1,[2,3.1],4,5,6]"), -1);
}

TestCase(TDCollateUnicodeStrings) {
    // Make sure that TDJSON never creates escape sequences we can't parse.
    // That includes "\unnnn" for non-ASCII chars, and "\t", "\b", etc.
    RequireTestCase(TDCollateConvertEscape);
    void* mode = kTDCollateJSON_Unicode;
    CAssertEq(collate(mode, encode(@"fréd"), encode(@"fréd")), 0);
    CAssertEq(collate(mode, encode(@"ømø"), encode(@"omo")), 1);
    CAssertEq(collate(mode, encode(@"\t"), encode(@" ")), -1);
    CAssertEq(collate(mode, encode(@"\001"), encode(@" ")), -1);
}
#endif
