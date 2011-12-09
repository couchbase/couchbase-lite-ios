//
//  ToyCollator.m
//  ToyCouch
//
//  Created by Jens Alfke on 12/8/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//
//  http://wiki.apache.org/couchdb/View_collation#Collation_Specification

#import "ToyCollate.h"


static int cmp(int n1, int n2) {
    int diff = n1 - n2;
    return diff > 0 ? 1 : (diff < 0 ? -1 : 0);
}

static int dcmp(double n1, double n2) {
    double diff = n1 - n2;
    return diff > 0.0 ? 1 : (diff < 0.0 ? -1 : 0);
}


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


static int compareStrings(const char** in1, const char** in2) {
    const char* str1 = *in1, *str2 = *in2;
    while(true) {
        ++str1;
        ++str2;

        // If one string ends, the other is greater; if both end, they're equal:
        if (*str1 == '"') {
            if (*str2 == '"')
                break;
            else
                return -1;
        } else if (*str2 == '"')
            return 1;
        
        // Un-escape the next character after a backslash:
        if (*str1 == '\\')
            ++str1;
        if (*str2 == '\\')
            ++str2;
        
        // Compare the next characters:
        int s = cmp(*str1, *str2);
        if (s)
            return s;
        //FIX: Need to do proper Unicode character collation on UTF-8 sequences
    }
    
    // Strings are equal, so update the positions:
    *in1 = str1 + 1;
    *in2 = str2 + 1;
    return 0;
}


int ToyCollate(void *context,
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
        if (type1 != type2)
            return cmp(type1, type2);
        // If types match, compare the actual token values:
        else switch (type1) {
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
                int diff = dcmp( strtod(str1, &next1), strtod(str2, &next2) );
                if (diff)
                    return diff;    // Numbers don't match
                str1 = next1;
                str2 = next2;
                break;
            }
            case kString: {
                int diff = compareStrings(&str1, &str2);
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



TestCase(ToyCollateScalars) {
    CAssertEq(ToyCollate(NULL, 0, "true", 0, "false"), 1);
    CAssertEq(ToyCollate(NULL, 0, "false", 0, "true"), -1);
    CAssertEq(ToyCollate(NULL, 0, "null", 0, "17"), -1);
    CAssertEq(ToyCollate(NULL, 0, "123", 0, "1"), 1);
    CAssertEq(ToyCollate(NULL, 0, "123", 0, "0123.0"), 0);
    CAssertEq(ToyCollate(NULL, 0, "123", 0, "\"123\""), -1);
    CAssertEq(ToyCollate(NULL, 0, "\"1234\"", 0, "\"123\""), 1);
    CAssertEq(ToyCollate(NULL, 0, "\"1234\"", 0, "\"1235\""), -1);
    CAssertEq(ToyCollate(NULL, 0, "\"1234\"", 0, "\"1234\""), 0);
    CAssertEq(ToyCollate(NULL, 0, "\"12\"34\"", 0, "\"1234\""), -1);
}

TestCase(ToyCollateArrays) {
    CAssertEq(ToyCollate(NULL, 0, "[]", 0, "\"foo\""), 1);
    CAssertEq(ToyCollate(NULL, 0, "[]", 0, "[]"), 0);
    CAssertEq(ToyCollate(NULL, 0, "[true]", 0, "[true]"), 0);
    CAssertEq(ToyCollate(NULL, 0, "[false]", 0, "[null]"), 1);
    CAssertEq(ToyCollate(NULL, 0, "[]", 0, "[null]"), -1);
    CAssertEq(ToyCollate(NULL, 0, "[123]", 0, "[45]"), 1);
    CAssertEq(ToyCollate(NULL, 0, "[123]", 0, "[45,67]"), 1);
    CAssertEq(ToyCollate(NULL, 0, "[123.4,\"wow\"]", 0, "[123.40,789]"), 1);
}

TestCase(ToyCollateNestedArrays) {
    CAssertEq(ToyCollate(NULL, 0, "[[]]", 0, "[]"), 1);
    CAssertEq(ToyCollate(NULL, 0, "[1,[2,3],4]", 0, "[1,[2,3.1],4,5,6]"), -1);
}
