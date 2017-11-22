//
//  CBLQuery+Predicates.m
//  Couchbase Lite
//
//  Created by Jens Alfke on 1/10/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLPredicateQuery+Internal.h"
#import "CBLDatabase+Internal.h"
#import "CBLCoreBridge.h"
#import "Fleece.h"

extern "C" {
#import "MYErrorUtils.h"
#import "Test.h"
}

#define kBadQuerySpecError -1
#define CBLErrorDomain @"CouchbaseLite"
#define mkError(ERR, FMT, ...)  MYReturnError(ERR, kBadQuerySpecError, CBLErrorDomain, \
                                              FMT, ## __VA_ARGS__)


typedef NS_OPTIONS(NSUInteger, CollationOptions) {
    kUnicode                = 1,
    kCaseInsensitive        = 2,
    kDiacriticInsensitive   = 4,
};


@implementation CBLPredicateQuery (Predicates)


// Translates an NSPredicate into the JSON-dictionary equivalent of a WHERE clause
+ (id) encodePredicate: (id)pred
                 error: (NSError**)outError
{
    if ([pred isKindOfClass: [NSArray class]] || [pred isKindOfClass: [NSDictionary class]]) {
        return pred;
    } else if ([pred isKindOfClass: [NSPredicate class]]) {
        return EncodePredicate(pred, outError);
    } else if ([pred isKindOfClass: [NSString class]]) {
        pred = [NSPredicate predicateWithFormat: (NSString*)pred argumentArray: nil];
        return EncodePredicate(pred, outError);
    } else {
        Assert(NO, @"Invalid specification for CBLPredicateQuery");
    }
}


// Translates an NSExpression into its LiteCore JSON-array equivalent
+ (id) encodeExpression: (NSExpression*)expr
              aggregate: (BOOL)aggregate
                  error: (NSError**)outError
{
    return EncodeExpression(expr, outError, aggregate);
}


// Encodes an array of NSExpressions (or NSStrings that compile into them) into JSON format.
+ (NSArray*) encodeExpressions: (NSArray*)exprs
                     aggregate: (BOOL)aggregate
                     collation: (BOOL)collation
                         error: (NSError**)outError
{
    NSMutableArray* result = [NSMutableArray new];
    for (id r in exprs) {
        id jsonObj = nil;
        if ([r isKindOfClass: [NSArray class]]) {
            jsonObj = r;
        } else {
            NSExpression* expr = nil;
            CollationOptions compareOptions = 0;
            if ([r isKindOfClass: [NSString class]]) {
                NSString* str = r;
                if (collation)
                    str = ExtractCollationSuffix(str, &compareOptions);
                expr = [NSExpression expressionWithFormat: str argumentArray: @[]];
            } else {
                Assert([r isKindOfClass: [NSExpression class]]);
                expr = r;
            }
            jsonObj = [self encodeExpression: expr aggregate: aggregate error: outError];
            if (!jsonObj)
                return nil;
            if (compareOptions)
                jsonObj = AddCollation(jsonObj, compareOptions);
        }
        [result addObject: jsonObj];
    }
    return result;
}


// Encodes an array of expressions all the way into JSON NSData.
+ (NSData*) encodeExpressionsToJSON: (NSArray*)expressions
                              error: (NSError**)outError
{
    NSArray* exprs = [self encodeExpressions: expressions
                                   aggregate: NO collation: NO
                                       error: outError];
    if (!exprs)
        return nil;
    return [NSJSONSerialization dataWithJSONObject: exprs options: 0 error: outError];
}


+ (NSArray*) encodeSortDescriptors: (NSArray*)sortDescriptors error: (NSError**)outError {
    NSMutableArray* sorts = [NSMutableArray new];
    for (id sd in sortDescriptors) {
        bool descending = false;
        CollationOptions collateOptions = 0;
        id key;
        // Each item of sortDescriptors can be an NSSortDescriptor, NSString or NSExpression:
        if ([sd isKindOfClass: [NSExpression class]]) {
            // ----NSExpression:
            key = [self encodeExpression: sd aggregate: true error: outError];
        } else {
            NSString* keyStr;
            if ([sd isKindOfClass: [NSString class]]) {
                // ----NSString:
                // Prefixing string with "-" signals descending order
                keyStr = sd;
                if ([keyStr hasPrefix: @"-"]) {
                    descending = true;
                    keyStr = [keyStr substringFromIndex: 1];
                }
                // Suffixing string with "[…]" sets collation
                if ([keyStr hasSuffix: @"]"]) {
                    keyStr = ExtractCollationSuffix(keyStr, &collateOptions);
                    if (!keyStr) {
                        mkError(outError, @"Invalid collation options in sort string \"%@\"", sd);
                        return nil;
                    }
                }

            } else {
                // ----NSSortDescriptor:
                Assert([sd isKindOfClass: [NSSortDescriptor class]]);
                descending = ![(NSSortDescriptor*)sd ascending];
                keyStr = [sd key];
                SEL selector = [sd selector];
                if (selector == @selector(localizedCompare:) ||
                            selector == @selector(localizedCaseInsensitiveCompare:)) {
                    collateOptions |= kUnicode;
                }
                if (selector == @selector(caseInsensitiveCompare:) ||
                            selector == @selector(localizedCaseInsensitiveCompare:)) {
                    collateOptions |= kCaseInsensitive;
                }
                // there's no NSString method for diacritic-insensitive compare...
            }

            // Convert keyStr to JSON as a rank() call or expression:
            if ([keyStr hasPrefix: @"rank("]) {
                if (![keyStr hasSuffix: @")"])
                    return mkError(outError, @"Invalid rank sort descriptor"), nil;
                NSString* indexName = [keyStr substringWithRange: {5, [keyStr length] - 6}];
                key = @[@"rank()", indexName];
            } else {
                NSExpression* expr = [NSExpression expressionWithFormat: keyStr argumentArray: @[]];
                key = [self encodeExpression: expr aggregate: true error: outError];
            }
        }
        if (!key)
            return nil;

        key = AddCollation(key, collateOptions);
        if (descending)
            key = @[@"DESC", key];
        [sorts addObject: key];
    }
    return sorts;
}


// Removes any bracketed set of collation flags from the end of a string and sets the corresponding
// flags in `outOptions`. Returns nil if there's a syntax error.
static NSString* ExtractCollationSuffix(NSString* sd, CollationOptions *outOptions) {
    if (![sd hasSuffix: @"]"])
        return sd;
    *outOptions |= kUnicode;
    NSInteger last = sd.length - 2;
    for (; last >= 0; --last) {
        unichar c = [sd characterAtIndex: last];
        if (c == '[')
            return [sd substringWithRange: {0, (NSUInteger)last}];
        else if (c == 'c')
            *outOptions |= kCaseInsensitive;
        else if (c == 'd')
            *outOptions |= kDiacriticInsensitive;
        else
            return nil;
    }
    return nil;
}


// https://github.com/couchbase/couchbase-lite-core/wiki/JSON-Query-Schema
// https://developer.apple.com/library/content/documentation/Cocoa/Conceptual/Predicates/Articles/pSyntax.html
// https://developer.apple.com/library/content/documentation/Cocoa/Conceptual/KeyValueCoding/CollectionOperators.html

// Maps NSPredicateOperatorType to query operator.
// See <Foundation/NSComparisonPredicate.h> lines 26-39
static NSString* const kPredicateOpNames[] = {
    @"<", @"<=", @">", @">=", @"=", @"!=",
    @"MATCH",           // Repurpose NSPredicate's MATCH as N1QL MATCH even though they're different
    @"GLOB",            // NSPredicate's "LIKE" is comparable to SQL/N1QL "GLOB", not "LIKE"
    nil, nil,           // TODO: Implement begins with, ends with
    @"IN",
    nil,                // 'custom selector'
};
static NSString* const kPredicateOpNames99[] = {
    @"CONTAINS()",
    @"BETWEEN"
};


// Maps NSExpression function selector to query operator.
// See <Foundation/NSExpression.h> lines 55-94
// https://developer.couchbase.com/documentation/server/4.5/n1ql/n1ql-language-reference/functions.html
static NSDictionary* const  kFunctionNames = @{ @"sum:":           @"ARRAY_SUM()",
                                                @"min:":           @"LEAST()",
                                                @"max:":           @"GREATEST()",
                                                @"add:to:":        @"+",
                                                @"from:subtract:": @"-",
                                                @"multiply:by:":   @"*",
                                                @"divide:by:":     @"/",
                                                @"modulus:by:":    @"%",
                                                @"count:":         @"ARRAY_COUNT()",
                                                @"sqrt:":          @"SQRT()",
                                                @"log:":           @"LOG()",
                                                @"ln:":            @"LN()",
                                                @"exp:":           @"EXP()",
                                                @"raise:toPower:": @"POWER()",
                                                @"floor:":         @"FLOOR()",
                                                @"ceiling:":       @"CEIL()",
                                                @"abs:":           @"ABS()",
                                                @"uppercase:":     @"UPPER()",
                                                @"lowercase:":     @"LOWER()",
                                                @"length:":        @"LENGTH()",
                                                // special cases (undocumented by Apple):
                                                @"valueForKeyPath:":        @".",
                                                @"objectFrom:withIndex:":   @"[]",
                                              };

// Function name mappings preferentially used if an aggregate expression is allowed.
static NSDictionary* const  kAggregateFunctionNames = @{@"sum:":           @"SUM()",
                                                        @"min:":           @"MIN()",
                                                        @"max:":           @"MAX()",
                                                        @"count:":         @"COUNT()",
                                                        };

// Other N1QL functions, that can be invoked in a format string as FUNCTION(rcvr, "FNNAME" [, ...])
static NSArray* kN1QLFunctionNames = @[@"REGEXP_LIKE", @"LEAST", @"GREATEST"];
static NSArray* kN1QLAggregateFunctionNames = @[];

// Encodes an NSPredicate.
static id EncodePredicate(NSPredicate* pred, NSError** outError) {
    if ([pred isKindOfClass: [NSComparisonPredicate class]]) {
        // Comparison of expressions, e.g. "a < b":
        NSComparisonPredicate* cp = (NSComparisonPredicate*)pred;
        id result = EncodeComparisonPredicate(cp, outError);
        if (!result)
            return nil;
        CollationOptions options = 0;
        if (cp.options & NSCaseInsensitivePredicateOption)
            options |= kCaseInsensitive | kUnicode;
        if (cp.options & NSDiacriticInsensitivePredicateOption)
            options |= kDiacriticInsensitive | kUnicode;
        result = AddCollation(result, options);
        return result;

    } else if ([pred isKindOfClass: [NSCompoundPredicate class]]) {
        // Logical compound of sub-predicates, e.g. "a AND b AND c":
        static NSString* const kCompoundOpNames[] = {@"NOT", @"AND", @"OR"};
        NSCompoundPredicate* cp = (NSCompoundPredicate*)pred;
        NSMutableArray *result = [NSMutableArray new];
        [result addObject: kCompoundOpNames[cp.compoundPredicateType]];
        for (NSPredicate* subPred in cp.subpredicates) {
            id obj = EncodePredicate(subPred, outError);
            if (!obj)
                return nil;
            [result addObject: obj];
        }
        return result;

    } else {
        return mkError(outError, @"Unsupported NSPredicate type %@", [pred class]), nil;
    }
}


// Encodes a predicate comparing expressions, e.g. "a < b". Does not apply collation.
static id EncodeComparisonPredicate(NSComparisonPredicate* cp, NSError** outError) {
    NSPredicateOperatorType opType = cp.predicateOperatorType;
    NSString *op = predicateOperatorName(opType);
    if (!op)
        return mkError(outError, @"Unsupported comparison operator %u", (unsigned)opType), nil;
    NSExpression* leftExpression = cp.leftExpression;
    NSExpression* rightExpression = cp.rightExpression;

    if (opType == NSBetweenPredicateOperatorType) {
        // BETWEEN needs some translation -- the range is in an array encoded in the RHS
        NSExpression* lhs = EncodeExpression(leftExpression, outError);
        if (!lhs) return nil;
        NSArray* range = rightExpression.collection;
        id min = EncodeExpression(range[0], outError);
        if (!min) return nil;
        id max = EncodeExpression(range[1], outError);
        if (!max) return nil;
        return @[op, lhs, min, max];
    }

    id rhs = EncodeExpression(rightExpression, outError);
    if (!rhs) return nil;
    updateOpForMissingOperand(rhs, opType, &op);

    if (opType == NSInPredicateOperatorType) {
        // IN needs translation if RHS is not a literal or property
        NSExpressionType rtype = rightExpression.expressionType;
        NSExpression* lhs = EncodeExpression(leftExpression, outError);
        if (!lhs) return nil;
        updateOpForMissingOperand(lhs, opType, &op);
        if (rtype != NSVariableExpressionType && rtype != NSAggregateExpressionType) {
            return @[@"ANY", @"X", rhs, @[@"=", @[@"?X"], lhs]];
        } else if (rtype == NSAggregateExpressionType)
            return @[op, lhs, rhs];
    }

    static NSString* const kModifiers[3] = {nil, @"EVERY", @"ANY"};
    NSString* mod = kModifiers[cp.comparisonPredicateModifier];
    if (mod == nil) {
        id lhs;
        if ([op isEqualToString: @"MATCH"])
            lhs = leftExpression.keyPath;
        else
            lhs = EncodeExpression(leftExpression, outError);
        if (!lhs) return nil;
        updateOpForMissingOperand(lhs, opType, &op);
        return @[op, lhs, rhs];
    } else {
        // ANY or EVERY modifiers: (I'm assuming they will always have a key-path as the LHS.)
        NSString* keyPath = leftExpression.keyPath;
        NSString* lastProp = nil;
        NSRange dot = [keyPath rangeOfString: @"." options: NSBackwardsSearch];
        if (dot.length > 0) {
            lastProp = [keyPath substringFromIndex: NSMaxRange(dot)];
            keyPath = [keyPath substringToIndex: dot.location];
        }
        return @[mod, @"X", encodeKeyPath(keyPath),
                 @[op, (lastProp ? @[@"?X", lastProp] : @[@"?X"]),
                   rhs]];
    }
}


static NSArray* AddCollation(id jsonExpr, CollationOptions optionFlags) {
    if (optionFlags != 0) {
        NSMutableDictionary* options = [NSMutableDictionary new];
        if (optionFlags & (kUnicode | kDiacriticInsensitive))
            options[@"UNICODE"] = @YES;
        if (optionFlags & kCaseInsensitive)
            options[@"CASE"] = @NO;
        if (optionFlags & kDiacriticInsensitive)
            options[@"DIAC"] = @NO;
        jsonExpr = @[@"COLLATE", options, jsonExpr];
    }
    return jsonExpr;
}


// Encodes an NSExpression.
static id EncodeExpression(NSExpression* expr, NSError **outError, bool aggregate =false) {
    switch (expr.expressionType) {
        case NSConstantValueExpressionType:
            return expr.constantValue ? expr.constantValue : @[@"MISSING"];
        case NSVariableExpressionType:
            return @[ [@"$" stringByAppendingString: expr.variable] ];
        case NSKeyPathExpressionType:
            for (NSString* prop in [expr.keyPath componentsSeparatedByString: @"."])
                if ([prop hasPrefix: @"@"])
                    return mkError(outError, @"Key-path collection operators not supported yet"), nil;
            return encodeKeyPath(expr.keyPath);
        case NSFunctionExpressionType:
            return EncodeFunction(expr, outError, aggregate);
        case NSConditionalExpressionType: {
            id condition = EncodePredicate(expr.predicate, outError);
            if (!condition) return nil;
            id ifTrue = EncodeExpression(expr.trueExpression, outError);
            if (!ifTrue) return nil;
            id ifFalse = EncodeExpression(expr.falseExpression, outError);
            if (!ifFalse) return nil;
            return @[@"CASE", [NSNull null], condition, ifTrue, ifFalse];
        }
        case NSAggregateExpressionType: {
            NSMutableArray* collection = [NSMutableArray arrayWithObject: @"[]"];
            for (id exp in expr.collection) {
                if ([exp isKindOfClass: [NSExpression class]])
                    [collection addObject: EncodeExpression(exp, outError, aggregate)];
                else
                    return mkError(outError, @"Invalid AggregateExpresion collection"), nil;
            }
            return collection;
        }
        default:
            if ((int)expr.expressionType == 11) {
                // Undocumented type; this seems to correspond to using one
                // of the reserved words (FIRST, LAST, SIZE...) as a property name.
                return encodeKeyPath(expr.description.lowercaseString);
            }
            return mkError(outError, @"Unsupported NSExpression type %u", (unsigned)expr.expressionType), nil;
    }
}


// Encodes a function NSExpression.
static id EncodeFunction(NSExpression* expr, NSError **outError, bool aggregateOK =false) {
    NSString *exprFunction = expr.function;
    NSString* fn = nil;
    if (aggregateOK && expr.arguments.count == 1)
        fn = kAggregateFunctionNames[exprFunction];
    if (fn == nil)
        fn = kFunctionNames[exprFunction];

    if (fn == nil) {
        exprFunction = [exprFunction uppercaseString];
        if ([kN1QLFunctionNames containsObject: exprFunction] ||
            (aggregateOK && [kN1QLAggregateFunctionNames containsObject: exprFunction]))
            fn = [exprFunction stringByAppendingString: @"()"];
        else
            return mkError(outError, @"Unsupported function '%@'", expr.function), nil;
    }

    if ([fn isEqualToString: @"."]) {
        // This is a weird case where using "first" or "last" in a key-path compiles to a
        // predicate containing an undocumented expression type...
        NSString* keyPath = [NSString stringWithFormat: @"%@.%@",
                             expr.operand.keyPath,
                             expr.arguments[0].description.lowercaseString];
        return encodeKeyPath(keyPath);
    } else if ([fn isEqualToString: @"[]"]) {
        // Array indexing: Ignore `operand`, it's undocumented _NSPredicateUtilities object.
        // The array and the index are the two elements of `arguments`.
        NSArray *operand = EncodeExpression(expr.arguments[0], outError);
        if (!operand) return nil;
        NSString* keyPath = operand[0];
        if (![keyPath hasPrefix: @"."])
            return mkError(outError, @"Can't index this as an array"), nil;
        id indexObj = EncodeExpression(expr.arguments[1], outError);
        if (!indexObj) return nil;
        NSInteger index;
        if ([indexObj isKindOfClass: [NSNumber class]])
            index = [indexObj integerValue];
        else if ([indexObj isEqual: @[@".first"]])
            index = 0;
        else if ([indexObj isEqual: @[@".last"]])
            index = -1;
        else if ([indexObj isEqual: @[@".size"]])
            return @[@"ARRAY_COUNT()", operand];
        else
            return mkError(outError, @"Array index must be constant"), nil;
        return @[ [NSString stringWithFormat: @"%@[%ld]", keyPath, (long)index] ];
    } else {
        // Regular function call:
        if ([fn isEqualToString: @"+"] && hasStringArgs(expr))
            fn = @"||";
        NSMutableArray* result = [NSMutableArray arrayWithObject: fn];
        NSExpression* operand = expr.operand;
        if (!isPredicateUtilities(operand)) {
            // some fn calls have an undocumented _NSPredicateUtilities constant as operand
            id p = EncodeExpression(operand, outError);
            if (!p) return nil;
            [result addObject: p];
        }
        for(NSExpression* param in expr.arguments) {
            id p = EncodeExpression(param, outError);
            if (!p) return nil;
            [result addObject: p];
        }
        return result;
    }
}


// Encodes a key-path as a property reference.
static NSArray* encodeKeyPath(NSString *keyPath) {
    return @[ [@"." stringByAppendingString: keyPath] ];
}


// Returns the N1QL operator name for a predicate operator type.
static NSString* predicateOperatorName(NSPredicateOperatorType op) {
    int iop = (int)op;
    NSString* const * table = kPredicateOpNames;
    int n = sizeof(kPredicateOpNames) / sizeof(NSString*);
    if (iop >= 99) {
        iop -= 99;
        table = kPredicateOpNames99;
        n = sizeof(kPredicateOpNames99) / sizeof(NSString*);
    }
    return (iop < n) ? table[iop] : nil;
}


// (In)equality comparisons against a value of 'missing' need to be expressed as IS / IS NOT.
static void updateOpForMissingOperand(id operand, NSPredicateOperatorType opType, NSString** op) {
    if ([operand isEqual: @[@"MISSING"]]) {
        if (opType == NSEqualToPredicateOperatorType)
            *op = @"IS";
        else if (opType == NSNotEqualToPredicateOperatorType)
            *op = @"IS NOT";
    }
}


// Returns true if the expression is known to have a string value.
static bool isStringValued(NSExpression* expr) {
    switch (expr.expressionType) {
        case NSConstantValueExpressionType:
            return [expr.constantValue isKindOfClass: [NSString class]];
        case NSFunctionExpressionType:
            return [@[@"uppercase:", @"lowercase:"] containsObject: expr.function];
        case NSConditionalExpressionType:
            return isStringValued(expr.trueExpression) || isStringValued(expr.falseExpression);
        default:
            return false;
    }
}


// Returns true if any of a function expression's arguments are known to be strings.
static bool hasStringArgs(NSExpression* expr) {
    if (isStringValued(expr.operand))
        return true;
    for (NSExpression* arg in expr.arguments)
        if (isStringValued(arg))
            return true;
    return false;
}


// Returns true if an expression represents the undocumented _NSPredicateUtilities object.
static bool isPredicateUtilities(NSExpression *expr) {
    return expr.expressionType == NSConstantValueExpressionType
        && [NSStringFromClass((Class)[expr.constantValue class])
                                                        isEqualToString: @"_NSPredicateUtilities"];
}


#pragma mark - DEBUGGING UTILITIES:


#if DEBUG
+ (void) dumpPredicate: (NSPredicate*)pred {
    DumpPredicate(pred, 0);
}


static void DumpPredicate(NSPredicate *pred, int indent) {
    for (int i=0; i < indent; i++) fprintf(stderr, "    ");
    fprintf(stderr, "%s ", NSStringFromClass(pred.class).UTF8String);
    if ([pred isKindOfClass: [NSComparisonPredicate class]]) {
        // Comparison of expressions, e.g. "a < b":
        NSComparisonPredicate* cp = (NSComparisonPredicate*)pred;
        fprintf(stderr, "%d; mod %d, opt %d\n",
                (int)cp.predicateOperatorType, (int)cp.comparisonPredicateModifier, (int)cp.options);
        DumpExpression(cp.leftExpression, indent+1);
        DumpExpression(cp.rightExpression, indent+1);
    } else if ([pred isKindOfClass: [NSCompoundPredicate class]]) {
        // Logical compound of sub-predicates, e.g. "a AND b AND c":
        static const char* const kCompoundOpNames[] = {"NOT", "AND", "OR"};
        NSCompoundPredicate* cp = (NSCompoundPredicate*)pred;
        fprintf(stderr, "%s\n", kCompoundOpNames[cp.compoundPredicateType]);
        for (NSPredicate *p in cp.subpredicates)
            DumpPredicate(p, indent+1);
    } else {
        fprintf(stderr, "???\n");
    }

}


static void DumpExpression(NSExpression* expr, int indent) {
    for (int i=0; i < indent; i++) fprintf(stderr, "    ");
    fprintf(stderr, "%s ", NSStringFromClass(expr.class).UTF8String);
    switch (expr.expressionType) {
        case NSConstantValueExpressionType:
            fprintf(stderr, "%s\n", [expr.constantValue description].UTF8String);
            return;
        case NSVariableExpressionType:
            fprintf(stderr, "%s\n", expr.variable.UTF8String);
            return;
        case NSKeyPathExpressionType:
            fprintf(stderr, "%s\n", expr.keyPath.UTF8String);
            return;
        case NSFunctionExpressionType: {
            fprintf(stderr, "%s\n", expr.function.UTF8String);
            DumpExpression(expr.operand, indent+1);
            for (NSExpression *arg in expr.arguments)
                DumpExpression(arg, indent+1);
            return;
        }
        case NSConditionalExpressionType:
            DumpPredicate(expr.predicate, indent+1);
            DumpExpression(expr.trueExpression, indent+1);
            DumpExpression(expr.falseExpression, indent+1);
            return;
        default:
            fprintf(stderr, "???\n");
            return;
    }
}


+ (NSString*) json5ToJSON: (const char*)json5 {
    return sliceResult2string(FLJSON5_ToJSON(FLSlice{json5, strlen(json5)}, NULL));
}
#endif

@end
