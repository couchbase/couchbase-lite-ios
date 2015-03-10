//
//  CBLQueryBuilder.m
//  Couchbase Lite
//
//  Created by Jens Alfke on 8/4/14.
//  Copyright (c) 2014-2015 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBLQueryBuilder.h"
#import "CBLQueryBuilder+Private.h"
#import "CBLReduceFuncs.h"
#import "CBJSONEncoder.h"
#import "CouchbaseLitePrivate.h"
#import "CBLMisc.h"


/*
    Three types of predicates:
    1. Map-time: Test in the map function, if false nothing's emitted.
    2. Range: Used to create the startKey/endKey in the query. Their expressions form the
        emitted keys.
    3. Filter: Post-process the returned query rows to check if they match.
 
    Predicates that don't involve any variables are map-time.
    Range predicates allow one equality test and one that can be equality or greater/less.
    All others have to be filters.
 
    When each type is evaluated, it can assume that the earlier predicates are true.
 */


// Attributes of an expression, as returned from -expressionAttributes:
typedef unsigned ExpressionAttributes;
enum {
    kExprUsesVariable = 1u,  // Does the expression involve a $-variable?
    kExprUsesDoc      = 2u   // Does the expression involve a doc property (key path)?
};


@implementation CBLQueryBuilder
{
    // These are only used during initialization:
    NSComparisonPredicate* _equalityKey;    // Predicate with equality test, used as key
    NSComparisonPredicate* _otherKey;       // Other predicate used as key
    NSArray* _keyPredicates;                // Predicates whose LHS generate the key, at map time
    NSString* _docType;                     // Document "type" property to restrict to
    NSArray* _valueTemplate;                // Values desired
    NSArray* _reduceFunctions;              // Name of reduce function to apply to each value
    NSMutableArray* _filterPredicates;      // Predicates to go into _queryFilter
    NSError* _error;                        // Set during -scanPredicate: if predicate is invalid

    // These will be used to initialize queries:
    NSExpression* _queryStartKey;           // The startKey to use in queries
    NSExpression* _queryEndKey;             // The endKey to use in queries
    NSExpression* _queryKeys;               // The 'keys' array to use in queries
    BOOL _queryInclusiveStart, _queryInclusiveEnd;  // The inclusiveStart/End to use in queries
    uint8_t _queryPrefixMatchLevel;         // The prefixMatchLevel to use in queries
    NSPredicate* _queryFilter;              // Postprocessing filter predicate to use in the query
    NSArray* _querySort;                    // Sort descriptors for the query

    // Used for -explanation
    BOOL _explodeKey;                       // Emit each item of key separately?
    NSPredicate* _mapPredicate;
}

@synthesize view=_view;

#if DEBUG // allow unit tests to inspect these internal properties
@synthesize mapPredicate=_mapPredicate, sortDescriptors=_querySort, filter=_queryFilter;
@synthesize queryStartKey=_queryStartKey, queryEndKey=_queryEndKey, queryKeys=_queryKeys;
@synthesize queryInclusiveStart=_queryInclusiveStart, queryInclusiveEnd=_queryInclusiveEnd;
@synthesize docType=_docType;
#endif


- (instancetype) initWithView: (CBLView*)view
                   inDatabase: (CBLDatabase*)database
                       select: (NSArray*)valueTemplate
               wherePredicate: (NSPredicate*)predicate
                      orderBy: (NSArray*)sortDescriptors
                        error: (NSError**)outError
{
    self = [super init];
    if (self) {
        _querySort = [sortDescriptors my_map: ^id(id descOrStr) {
            return [CBLQueryEnumerator asNSSortDescriptor: descOrStr];
        }];

        // Scan the input:
        [self scanValueTemplate: valueTemplate];  // sets _valueTemplate, _reduceFunctions
        BOOL anyVars;
        _filterPredicates = [NSMutableArray array];
        _mapPredicate = [self scanPredicate: predicate anyVariables: &anyVars];

        if (_error) {
            if (outError)
                *outError = _error;
            return nil;
        }

        _keyPredicates = [self createKeyPredicates];
        _querySort = [self createQuerySortDescriptors];
        _queryFilter = [self createQueryFilter];

        if (_keyPredicates.count == 0) {
            // If no key is needed, just emit an empty string as the key
            _keyPredicates = @[ [NSPredicate predicateWithFormat: @"'' == ''"] ];
        }

        // If the predicate contains a "property CONTAINS $item" test, then we should emit every
        // item of the 'property' array as a separate key during the map phase.
        _explodeKey = (_equalityKey.predicateOperatorType == NSContainsPredicateOperatorType);

        if (database) {
            // (We allow a nil database and just skip creating a view; useful for unit tests.)
            _view = [[self class] defineView: view
                                  inDatabase: database
                            withMapPredicate: _mapPredicate
                               keyExpression: self.keyExpression
                                  explodeKey: _explodeKey
                                documentType: _docType
                             valueExpression: self.valueExpression
                             reduceFunctions: _reduceFunctions];
        }

        [self precomputeQuery];

        LogTo(Query, @"Created CBLQueryBuilder on %@:\n%@", view, self.explanation);
    }
    return self;
}


- (instancetype) initWithDatabase: (CBLDatabase*)database
                           select: (NSArray*)valueTemplate
                   wherePredicate: (NSPredicate*)predicate
                          orderBy: (NSArray*)sortDescriptors
                            error: (NSError**)outError
{
    return [self initWithView: nil inDatabase: database select: valueTemplate
               wherePredicate:predicate orderBy: sortDescriptors error: outError];
}


- (instancetype) initWithView: (CBLView*)view
                       select: (NSArray*)valueTemplate
               wherePredicate: (NSPredicate*)predicate
                      orderBy: (NSArray*)sortDescriptors
                        error: (NSError**)outError
{
    return [self initWithView: view inDatabase: view.database select: valueTemplate
               wherePredicate:predicate orderBy: sortDescriptors error: outError];
}


- (instancetype) initWithDatabase: (CBLDatabase*)database
                           select: (NSArray*)valueTemplate
                            where: (NSString*)predicate
                          orderBy: (NSArray*)sortDescriptors
                            error: (NSError**)outError
{
    return [self initWithDatabase: database
                       select: valueTemplate
               wherePredicate: [NSPredicate predicateWithFormat: predicate argumentArray: nil]
                      orderBy: sortDescriptors
                        error: outError];
}


#if 0 // (Does it make sense to make this class archivable??)
- (void) encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject: _queryStartKey         forKey: @"queryStartKey"];
    [coder encodeObject: _queryEndKey           forKey: @"queryEndKey"];
    [coder encodeObject: _queryKeys             forKey: @"queryKeys"];
    [coder encodeBool:   _queryInclusiveStart   forKey: @"queryInclusiveStart"];
    [coder encodeBool:   _queryInclusiveEnd     forKey: @"queryInclusiveEnd"];
    [coder encodeObject: _queryFilter           forKey: @"queryFilter"];
    [coder encodeObject: _querySort             forKey: @"querySort"];
    [coder encodeObject: _mapPredicate          forKey: @"mapPredicate"];
    [coder encodeObject: _view.name             forKey: @"viewName"];
}


- (instancetype) initWithCoder:(NSCoder *)decoder {
    self = [super init];
    if (self) {
        _queryStartKey      = [decoder decodeObjectForKey: @"queryStartKey"];
        _queryEndKey        = [decoder decodeObjectForKey: @"queryEndKey"];
        _queryKeys          = [decoder decodeObjectForKey: @"queryKeys"];
        _queryInclusiveStart= [decoder decodeBoolForKey:   @"queryInclusiveStart"];
        _queryInclusiveEnd  = [decoder decodeBoolForKey:   @"queryInclusiveEnd"];
        _queryFilter        = [decoder decodeObjectForKey: @"queryFilter"];
        _querySort          = [decoder decodeObjectForKey: @"querySort"];
        _mapPredicate       = [decoder decodeObjectForKey: @"mapPredicate"];
        NSString* viewName  = [decoder decodeObjectForKey: @"viewName"];
    }
    return self;
}
#endif


// Makes a printed expression more JavaScript-like by changing array brackets from {} to [].
static NSString* printExpr(NSExpression* expr) {
    NSString* desc = expr.description;
    if ([desc hasPrefix: @"{"] && [desc hasSuffix: @"}"])
        desc = $sprintf(@"[%@]", [desc substringWithRange: NSMakeRange(1, desc.length-2)]);
    return desc;
}


- (NSString*) explanation {
    NSMutableString* out = [NSMutableString string];
    if (_view)
        [out appendFormat: @"// view \"%@\":\n", _view.name];
    [out appendString: @"view.map = {\n"];
    if (_mapPredicate)
        [out appendFormat: @"    if (%@)\n    ", _mapPredicate];
    NSString* keyExprStr = printExpr(self.keyExpression);
    NSString* valExprStr = printExpr(self.valueExpression);
    if (_explodeKey) {
        NSExpression* keyExpression = self.keyExpression;
        if (keyExpression.expressionType != NSAggregateExpressionType) {
            // looping over simple key:
            [out appendFormat: @"    for (i in %@)\n", keyExprStr];
            if (_mapPredicate)
                [out appendString: @"    "];
            [out appendFormat: @"        emit(i, %@);\n};\n", valExprStr];
        } else {
            // looping over compound key:
            NSArray* keys = keyExpression.collection;
            [out appendFormat: @"    for (i in %@)\n", keys[0]];
            if (_mapPredicate)
                [out appendString: @"    "];
            NSArray* restOfKey = [keys subarrayWithRange: NSMakeRange(1, keys.count-1)];
            [out appendFormat: @"        emit([i, %@], %@);\n};\n",
                 [restOfKey componentsJoinedByString: @", "], valExprStr];
        }
    } else {
        [out appendFormat: @"    emit(%@, %@);\n};\n", keyExprStr, valExprStr];
    }

    if (_reduceFunctions.count > 0) {
        if (_reduceFunctions.count == 1) {
            NSString* fn = _reduceFunctions[0];
            NSString* impl = [fn stringByAppendingString: @"(values)"];
            [out appendFormat: @"view.reduce = {return %@;}\n", impl];
        } else {
            NSString* impl = [[_reduceFunctions my_map: ^NSString*(NSString* fn) {
                return [fn stringByAppendingString: @"(values)"];
                //FIX: "(values)" is misleading; it's really the i'th element of each value
            }] componentsJoinedByString: @", "];
            [out appendFormat: @"view.reduce = {return [%@];}\n", impl];
        }
    }

    if (_queryKeys) {
        [out appendFormat: @"query.keys = %@;\n", _queryKeys];
    } else {
        if (_queryStartKey)
            [out appendFormat: @"query.startKey = %@;\n", printExpr(_queryStartKey)];
        if (!_queryInclusiveStart)
            [out appendFormat: @"query.inclusiveStart = NO;\n"];
        if (_queryEndKey)
            [out appendFormat: @"query.endKey = %@;\n", printExpr(_queryEndKey)];
        if (!_queryInclusiveEnd)
            [out appendString: @"query.inclusiveEnd = NO;\n"];
        if (_queryPrefixMatchLevel)
            [out appendFormat: @"query.prefixMatchLevel = %u;\n", _queryPrefixMatchLevel];
    }
    if (_queryFilter)
        [out appendFormat: @"query.postFilter = %@;\n", _queryFilter];
    if (_querySort)
        [out appendFormat: @"query.sortDescriptors = [%@];\n",
                                [_querySort componentsJoinedByString: @", "]];
    return out;
}


#pragma mark - PARSING THE INPUT:


// Recursively scans the predicate at initialization time looking for variables.
// Predicates using variables are stored in _equalityKey and _otherKey, and removed from the
// overall predicate. (If nothing is left, returns nil.)
// *outAnyVariables will be set to YES if the predicate contains any variables.
- (NSPredicate*) scanPredicate: (NSPredicate*)pred
                  anyVariables: (BOOL*)outAnyVariables
{
    if ([pred isKindOfClass: [NSComparisonPredicate class]]) {
        // Comparison of expressions, e.g. "a < b":
        NSComparisonPredicate* cp = (NSComparisonPredicate*)pred;

        // Check if cp is of the form `type = "..."`, set _docType to the RHS string.
        // (Don't factor this term out of the containing predicate by returning nil: it might
        // turn out we can't use this for _docType, if the containing predicate is an OR or NOT,
        // and in that case we should leave the predicate alone to be tested at map-type.)
        [self lookForDocTypeEqualityTest: cp];

        ExpressionAttributes lhs = [self expressionAttributes: cp.leftExpression];
        ExpressionAttributes rhs = [self expressionAttributes: cp.rightExpression];
        if (!((lhs|rhs) & kExprUsesVariable))
            return cp;      // Neither side uses a variable

        if (((lhs & kExprUsesVariable) && (lhs & kExprUsesDoc))) {
            [self fail: @"Expression mixes doc properties and variables: %@", cp.leftExpression];
            return nil;
        }
        if (((rhs & kExprUsesVariable) && (rhs & kExprUsesDoc))) {
            [self fail: @"Expression mixes doc properties and variables: %@", cp.rightExpression];
            return nil;
        }

        // Comparison involves a variable, so save variable expression as a key:
        if (lhs & kExprUsesVariable) {
            if (rhs & kExprUsesVariable) {
                [self fail: @"Both sides can't use variables: %@", pred];
                return nil;
            }
            NSComparisonPredicate* flipped = flipComparison(cp); // Always put variable on RHS
            if (!flipped)
                [_filterPredicates addObject: cp];  // Not flippable; save for post-filter
            cp = flipped;
        }
        if (cp)
            [self addKeyPredicate: cp];
        // Result of this comparison is unknown at indexing time, so return nil:
        *outAnyVariables = YES;
        return nil;

    } else if ([pred isKindOfClass: [NSCompoundPredicate class]]) {
        // Logical compound of sub-predicates, e.g. "a AND b AND c":
        NSCompoundPredicate* cp = (NSCompoundPredicate*)pred;
        __block BOOL anyVars = NO;
        NSArray* subpredicates = [cp.subpredicates my_map: ^NSPredicate*(NSPredicate* sub) {
            return [self scanPredicate: sub anyVariables: &anyVars];
        }];
        if (_error)
            return nil;
        if (anyVars)
            *outAnyVariables = YES;
        if (cp.compoundPredicateType != NSAndPredicateType) {
            if (anyVars) {
                [self fail: @"Sorry, the OR and NOT operators aren't supported with variables yet"];
                return nil;
            }
            _docType = nil; // can't use `type="..."` check if it's inside an OR or NOT
        }
        if (subpredicates.count == 0)
            return nil;                 // all terms are variable, so return unknown
        else if (subpredicates.count == 1 && cp.compoundPredicateType != NSNotPredicateType)
            return subpredicates[0];    // AND or OR of one predicate, so just return it
        else
            return [[NSCompoundPredicate alloc] initWithType: cp.compoundPredicateType
                                               subpredicates: subpredicates];

    } else {
        [self fail: @"Unsupported predicate type '%@': %@", [pred class], pred];
        return nil;
    }
}


// During scanning, saves a comparison predicate to be used as a key.
// Returns YES if the predicate can be used to create a range for the query,
// NO if it has to run after the query.
- (BOOL) addKeyPredicate: (NSComparisonPredicate*)cp {
    NSPredicateOperatorType op = cp.predicateOperatorType;
    if (!_equalityKey && (op == NSEqualToPredicateOperatorType ||
                          op == NSContainsPredicateOperatorType ||
                          op == NSInPredicateOperatorType)) {
        // An equality (or containment) test can become the primary key.
        _equalityKey = cp;
        return YES;
    } else if (!_otherKey && (op <= NSEqualToPredicateOperatorType ||
                              op == NSBetweenPredicateOperatorType ||
                              op == NSBeginsWithPredicateOperatorType)) {
        // A less/greater test or range or begins-with can become secondary key (or primary
        // if no equality test is present.)
        _otherKey = cp;
        return YES;
    } else if (_otherKey) {
        // Otherwise let's see if we can merge this comparison into an existing key predicate:
        NSComparisonPredicate* merged = mergeComparisons(cp, _otherKey);
        if (merged) {
            _otherKey = merged;
            return YES;
        }
    }

    // If we fell through, cp can't be used as part of the key, so save it for query time:
    [_filterPredicates addObject: cp];
    return NO;
}


// Returns YES if an NSExpression's value involves evaluating a variable.
- (ExpressionAttributes) expressionAttributes: (NSExpression*)expression {
    switch (expression.expressionType) {
        case NSVariableExpressionType:
            return kExprUsesVariable;
        case NSKeyPathExpressionType:
            return kExprUsesDoc;
        case NSConstantValueExpressionType:
            return 0;
        case NSUnionSetExpressionType:
        case NSIntersectSetExpressionType:
        case NSMinusSetExpressionType:
            return [self expressionAttributes: expression.leftExpression]
                 | [self expressionAttributes: expression.rightExpression];
        case NSFunctionExpressionType: {
            ExpressionAttributes attrs = 0;
            for (NSExpression* expr in expression.arguments)
                attrs |= [self expressionAttributes: expr];
            return attrs;
        }
        case NSAggregateExpressionType: {
            ExpressionAttributes attrs = 0;
            for (NSExpression* expr in expression.collection)
                attrs |= [self expressionAttributes: expr];
            return attrs;
        }
        default:
            [self fail: @"Unsupported expression type %d: %@",
                   (int)expression.expressionType, expression];
            return 0;
    }
}


- (void) scanValueTemplate: (NSArray*)valueTemplate {
    if (!valueTemplate)
        return;
    NSMutableArray* reduceFns = $marray();
    _valueTemplate = [valueTemplate my_map: ^id(id value) {
        NSExpression* expr = $castIf(NSExpression, value);
        if (expr.expressionType == NSFunctionExpressionType) {
            NSString* fnName = expr.function;
            if ([fnName hasSuffix: @":"]) {
                fnName = [fnName substringToIndex: fnName.length-1];
                if (CBLGetReduceFunc(fnName)) {
                    // This value is using an aggregate function like sum() or average(). Save the fn
                    // name, and make the emitted value be the reduce function name:
                    [reduceFns addObject: fnName];
                    return expr.arguments[0];
                }
            }
        }
        return value; // default
    }];

    if (reduceFns.count == valueTemplate.count)
        _reduceFunctions = [reduceFns copy];
    else if (reduceFns.count > 0)
        [self fail: @"Can't have both regular and reduced/aggregate values"];
}


// If this is of the form "type = '...'", returns the string.
- (BOOL) lookForDocTypeEqualityTest: (NSComparisonPredicate*)cp {
    if (_docType)
        return NO;
    if (cp.predicateOperatorType == NSEqualToPredicateOperatorType) {
        NSExpression* lhs = cp.leftExpression;
        NSExpression* rhs = cp.rightExpression;
        if (lhs.expressionType == NSKeyPathExpressionType
                && [lhs.keyPath isEqualToString: @"type"]
                && rhs.expressionType == NSConstantValueExpressionType
                && [rhs.constantValue isKindOfClass: [NSString class]]) {
            _docType = rhs.constantValue;
            return YES;
        }
    }
    return NO;
}


#pragma mark - FILTER PREDICATE & SORT DESCRIPTORS:


- (NSPredicate*) createQueryFilter {
    // Update each of _filterPredicates to make its keypath relative to the query rows' values.
    for (NSUInteger i = 0; i < _filterPredicates.count; ++i) {
        NSComparisonPredicate* cp = _filterPredicates[i];
        cp = [[NSComparisonPredicate alloc]
                  initWithLeftExpression: [self rewriteKeyPathsInExpression: cp.leftExpression]
                         rightExpression: [self rewriteKeyPathsInExpression: cp.rightExpression]
                                modifier: cp.comparisonPredicateModifier
                                    type: cp.predicateOperatorType
                                 options: cp.options];
        [_filterPredicates replaceObjectAtIndex: i withObject: cp];
    }
    // Combine the filterPredicates into a single predicate:
    switch (_filterPredicates.count) {
        case 0:
            return nil;
        case 1:
            return _filterPredicates[0];
        default:
            return [[NSCompoundPredicate alloc] initWithType: NSAndPredicateType
                                               subpredicates: _filterPredicates];
    }
}


// Traverses an NSExpression fixing up keypaths via -rewriteKeyPath:.
- (NSExpression*) rewriteKeyPathsInExpression: (NSExpression*)expression {
    switch (expression.expressionType) {
        case NSKeyPathExpressionType: {
            NSString* keyPath = [self rewriteKeyPath: expression.keyPath];
            return [NSExpression expressionForKeyPath: keyPath];
        }
        case NSFunctionExpressionType: {
            NSArray* args = [self rewriteKeyPathsInExpressions: expression.arguments];
            return [NSExpression expressionForFunction: expression.function arguments: args];
        }
        case NSUnionSetExpressionType:
        case NSIntersectSetExpressionType:
        case NSMinusSetExpressionType: {
            NSExpression* lhs = [self rewriteKeyPathsInExpression: expression.leftExpression];
            NSExpression* rhs = [self rewriteKeyPathsInExpression: expression.rightExpression];
            switch (expression.expressionType) {
                case NSUnionSetExpressionType:
                    return [NSExpression expressionForUnionSet: lhs with: rhs];
                case NSIntersectSetExpressionType:
                    return [NSExpression expressionForIntersectSet: lhs with: rhs];
                case NSMinusSetExpressionType:
                default:
                    return [NSExpression expressionForMinusSet: lhs with: rhs];
            }
        }
        case NSAggregateExpressionType: {
            NSArray* collection = [self rewriteKeyPathsInExpressions: expression.collection];
            return [NSExpression expressionForAggregate: collection];
        }
        case NSVariableExpressionType:
        case NSConstantValueExpressionType:
        case NSEvaluatedObjectExpressionType:
        case NSAnyKeyExpressionType:
            return expression;
        default:
            [self fail: @"Unsupported expression type %d: %@",
                         (int)expression.expressionType, expression];
            return nil;
    }
}


// Traverses an array of NSExpressions fixing up keypaths via -rewriteKeyPath:.
- (NSArray*) rewriteKeyPathsInExpressions: (NSArray*)expressions {
    NSMutableArray* result = [NSMutableArray array];
    for (NSExpression* expr in expressions)
        [result addObject: [self rewriteKeyPathsInExpression: expr]];
    return result;
}


// Changes a key-path into one that can be used on a CBLQueryRow, i.e. a reference to an indexed
// key or value.
- (NSString*) rewriteKeyPath: (NSString*)keyPath {
    // First, is this the key or a component of it?
    unsigned index = 0;
    for (NSComparisonPredicate* kp in _keyPredicates) {
        NSExpression* keyExpr = kp.leftExpression;
        if (keyExpr.expressionType == NSKeyPathExpressionType
                && [keyExpr.keyPath isEqualToString: keyPath]) {
            return [NSString stringWithFormat: @"key%u", index];
        }
        ++index;
    }

    // Look it up in the emitted values, or add it if not present:
    if (_valueTemplate) {
        NSUInteger index = [_valueTemplate indexOfObject: keyPath];
        if (index == NSNotFound) {
            index = [_valueTemplate count];
            _valueTemplate = [_valueTemplate arrayByAddingObject: keyPath];
        }
        return [NSString stringWithFormat: @"value%lu", (unsigned long)index];
    } else {
        _valueTemplate = @[keyPath];
        return @"value0";
    }
}


// Finds the expression(s) whose values (at map time) are to be emitted as the key.
- (NSArray*) createKeyPredicates {
    NSMutableArray* keyPredicates = [NSMutableArray array];
    if (_equalityKey)
        [keyPredicates addObject: _equalityKey];
    if (_otherKey)
        [keyPredicates addObject: _otherKey];
    else if (allAscendingSorts(_querySort)) {
        // Add sort descriptors as extra components of the key so the index will sort by them:
        NSUInteger i = 0;
        for (NSSortDescriptor* sortDesc in _querySort) {
            NSExpression* expr = [NSExpression expressionForKeyPath: sortDesc.key];
            if (i++ == 0 && [expr isEqual: _equalityKey.leftExpression])
                continue;   // This sort descriptor is already the 1st component of the key
            NSComparisonPredicateOptions options = 0;
            if (sortDesc.selector == @selector(caseInsensitiveCompare:))
                options |= NSCaseInsensitivePredicateOption;
            [keyPredicates addObject: [NSComparisonPredicate
                    predicateWithLeftExpression: expr
                                rightExpression: [NSExpression expressionForConstantValue: nil]
                                       modifier: NSDirectPredicateModifier
                                           type: NSLessThanPredicateOperatorType
                                        options: options]];
        }
        _querySort = nil;
    }

    // Remove redundant values that are already part of the key:
    NSMutableArray* values = [_valueTemplate mutableCopy];
    for (NSComparisonPredicate* cp in keyPredicates) {
        NSExpression* expr = cp.leftExpression;
        if (expr.expressionType == NSKeyPathExpressionType && cp.options == 0) {
            [values removeObject: expr];
            [values removeObject: expr.keyPath];
        }
    }
    _valueTemplate = [values copy];

    return keyPredicates;
}


// Computes the post-processing sort descriptors to be applied after the query runs.
- (NSArray*) createQuerySortDescriptors {
    if (_querySort.count == 0)
        return nil;

    NSMutableArray* sort = [NSMutableArray arrayWithCapacity: _querySort.count];
    for (NSSortDescriptor* sd in _querySort) {
        [sort addObject: [[NSSortDescriptor alloc] initWithKey: [self rewriteKeyPath: sd.key]
                                                     ascending: sd.ascending
                                                      selector: sd.selector]];
    }
    return sort;
}


#pragma mark - DEFINING THE VIEW:


// The expression that should be emitted as the key
- (NSExpression*) keyExpression {
    return combineExpressions([_keyPredicates my_map: ^id(NSComparisonPredicate* cp) {
        NSExpression* expr = cp.leftExpression;
        if (cp.options & NSCaseInsensitivePredicateOption)
            expr = [NSExpression expressionForFunction: @"lowercase:" arguments: @[expr]];
        return expr;
    }]);
}


// The expression that should be emitted as the value
- (NSExpression*) valueExpression {
    return combineExpressions([_valueTemplate my_map: ^id(id item) {
        if (![item isKindOfClass: [NSExpression class]])
            item = [NSExpression expressionForKeyPath: $castIf(NSString, item)];
        return item;
    }]);
}


// Sets the view's map block. (This is a class method to avoid having the block accidentally close
// over any instance variables, creating a reference cycle.)
+ (CBLView*) defineView: (CBLView*)view
             inDatabase: (CBLDatabase*)db
       withMapPredicate: (NSPredicate*)mapPredicate
          keyExpression: (NSExpression*)keyExpression
             explodeKey: (BOOL)explodeKey
           documentType: (NSString*)docType
        valueExpression: (NSExpression*)valueExpr
        reduceFunctions: (NSArray*)reduceFunctions
{
    // Compute a map-block version string that's unique to this configuration:
    NSString* version = CBLDigestFromObject($dict( {@"key",    keyExpression.description},
                                                   {@"map",    mapPredicate.predicateFormat},
                                                   {@"value",  valueExpr.description},
                                                   {@"reduce", reduceFunctions},
                                                   {@"docType", docType} ));
    if (!view) {
        NSString* viewID = [NSString stringWithFormat: @"builder-%@", version];
        if (![db existingViewNamed: viewID]) {
            // Logging makes it easier to detect misuse where someone creates lots of builders with
            // slightly different predicates containing hardcoded variable values, which will
            // result in lots of unnecessary views being created.
            // (For example, "doc.price < 100", "doc.price < 50", "doc.price < 200" ...
            // instead of "doc.price < $PRICE" with $PRICE being filled in at query time.)
            Log(@"CBLQueryBuilder: Creating new view '%@'", viewID);
        }
        view = [db viewNamed: viewID];
    }

    view.documentType = docType;

    BOOL compoundKey = (keyExpression.expressionType == NSAggregateExpressionType);

    // Define the view's map block:
    [view setMapBlock: ^(NSDictionary *doc, CBLMapEmitBlock emit) {
        if (!mapPredicate || [mapPredicate evaluateWithObject: doc]) {  // check mapPredicate
            id key = [keyExpression expressionValueWithObject: doc context: nil];
            id value = [valueExpr expressionValueWithObject: doc context: nil];
            if (!key)
                return;
            if (!explodeKey) {
                emit(key, value); // regular case
            } else if (![key isKindOfClass: [NSArray class]]) {
                if ([key isKindOfClass: [NSString class]])
                    Warn(@"CBLQueryBuilder: '%@ contains...' expected %@ to be an array"
                        " but it's a string; remember not to use 'contains' as a string operation!",
                         keyExpression, keyExpression);
                return;
            } else if (!compoundKey) {
                // 'contains' test with single key; iterate over key:
                for (id keyItem in key)
                    emit(keyItem, value);
            } else {
                // 'contains' test with compound key; iterate over key[0], replacing it with each
                // element in turn and emitting that as the key:
                if ([key count] == 0)
                    return;
                NSArray* key0 = key[0];
                if (![key0 isKindOfClass: [NSArray class]])
                    return;
                NSMutableArray* eachKey = [key mutableCopy];
                for (id keyItem in key0) {
                    eachKey[0] = keyItem;
                    emit(eachKey, value);
                }
            }
        }
    } reduceBlock: [self defineReduceBlockForFunctions: reduceFunctions]
          version: version];
    return view;
}


// Creates a reduce block given an array of function names corresponding to the emitted values.
+ (CBLReduceBlock) defineReduceBlockForFunctions: (NSArray*)functions {
    if (functions.count == 0)
        return nil;
    else if (functions.count == 1)
        return CBLGetReduceFunc(functions[0]);
    else
        Assert(NO, @"Can't handle multiple reduced values yet");
}


#pragma mark - QUERYING:


static NSExpression* keyExprForQuery(NSComparisonPredicate* cp) {
    NSExpression* rhs = cp.rightExpression;
    if (cp.options & NSCaseInsensitivePredicateOption)
        rhs = [NSExpression expressionForFunction: @"lowercase:" arguments: @[rhs]];
    return rhs;
}


// Creates the query startKey/endKey expressions and the inclusive start/end values.
// This is called at initialization time only.
- (BOOL) precomputeQuery {
    _queryInclusiveStart = _queryInclusiveEnd = YES;

    if (_equalityKey.predicateOperatorType == NSInPredicateOperatorType) {
        // Using "key in $SET", so query should use .keys instead of .startKey/.endKey
        _queryKeys = keyExprForQuery(_equalityKey);
        return YES;
    }

    NSMutableArray* startKey = [NSMutableArray array];
    NSMutableArray* endKey   = [NSMutableArray array];

    if (_equalityKey) {
        // The LHS is the expression emitted as the view's key, and the RHS is a variable
        NSExpression* keyExpr = keyExprForQuery(_equalityKey);
        [startKey addObject: keyExpr];
        [endKey   addObject: keyExpr];
    }

    if (_otherKey) {
        NSExpression* keyExpr = keyExprForQuery(_otherKey);
        NSPredicateOperatorType op = _otherKey.predicateOperatorType;
        switch (op) {
            case NSLessThanPredicateOperatorType:
            case NSLessThanOrEqualToPredicateOperatorType:
                [endKey addObject: keyExpr];
                _queryInclusiveEnd = (op == NSLessThanOrEqualToPredicateOperatorType);
                break;
            case NSEqualToPredicateOperatorType:
                [startKey addObject: keyExpr];
                [endKey addObject: keyExpr];
                break;
            case NSGreaterThanOrEqualToPredicateOperatorType:
            case NSGreaterThanPredicateOperatorType:
                [startKey addObject: keyExpr];
                _queryInclusiveStart = (op == NSGreaterThanOrEqualToPredicateOperatorType);
                if (endKey.count > 0)
                    [endKey addObject: @{}];
                break;
            case NSBeginsWithPredicateOperatorType:
                [startKey addObject: keyExpr];
                [endKey addObject: keyExpr];
                _queryPrefixMatchLevel = 1;
                break;
            case NSBetweenPredicateOperatorType: {
                // key must be an aggregate expression:
                NSArray* aggregate = keyExpr.collection;
                [startKey addObject: aggregate[0]];
                [endKey   addObject: aggregate[1]];
                break;
            }
            default:
                Warn(@"Unsupported operator (#%d) in %@", (int)op, _otherKey);
                return NO;
        }
    }

    if (_keyPredicates.count > 1) {
        _queryStartKey = [NSExpression expressionForAggregate: startKey];
        _queryEndKey   = [NSExpression expressionForAggregate: endKey];
        if (endKey.count < _keyPredicates.count)
            _queryPrefixMatchLevel = 1;
    } else {
        _queryStartKey = startKey.firstObject;
        _queryEndKey   = endKey.firstObject;
    }
    return YES;
}


// Public method to create a CBLQuery.
- (CBLQuery*) createQueryWithContext: (NSDictionary*)context {
    NSMutableDictionary* mutableContext = [context mutableCopy];
    CBLQuery* query = [_view createQuery];

    if (_queryKeys) {
        id keys = [_queryKeys expressionValueWithObject: nil context: mutableContext];
        if ([keys isKindOfClass: [NSDictionary class]] || [keys isKindOfClass: [NSSet class]])
            keys = [keys allValues];
        query.keys = $cast(NSArray, keys);
        
    } else {
        query.startKey = [_queryStartKey expressionValueWithObject: nil context: mutableContext];
        query.endKey = [_queryEndKey expressionValueWithObject: nil context: mutableContext];
        query.inclusiveStart = _queryInclusiveStart;
        query.inclusiveEnd = _queryInclusiveEnd;
        query.prefixMatchLevel = _queryPrefixMatchLevel;
    }
    query.sortDescriptors = _querySort;
    query.postFilter = [_queryFilter predicateWithSubstitutionVariables: mutableContext];
    return query;
}


- (CBLQueryEnumerator*) runQueryWithContext: (NSDictionary*)context
                                      error: (NSError**)outError {
    return [[self createQueryWithContext: context] run: outError];
}


#pragma mark - UTILITIES:


- (void) fail: (NSString*)message, ... NS_FORMAT_FUNCTION(1,2) {
    if (!_error) {
        va_list args;
        va_start(args, message);
        message = [[NSString alloc] initWithFormat: message arguments: args];
        va_end(args);
        NSDictionary* userInfo = @{NSLocalizedFailureReasonErrorKey: message};
        _error = [NSError errorWithDomain: @"CBLQueryBuilder" code: -1 userInfo: userInfo];
    }
}


static bool allAscendingSorts(NSArray* sortDescriptors) {
    for (NSSortDescriptor* s in sortDescriptors)
        if (!s.ascending)
            return NO;
    return YES;
}


// Reverses the order of terms in a comparison without affecting its meaning.
static NSComparisonPredicate* flipComparison(NSComparisonPredicate* cp) {
    static NSPredicateOperatorType kFlipped[1+NSNotEqualToPredicateOperatorType] = {
        NSGreaterThanPredicateOperatorType,
        NSGreaterThanOrEqualToPredicateOperatorType,
        NSLessThanPredicateOperatorType,
        NSLessThanOrEqualToPredicateOperatorType,
        NSEqualToPredicateOperatorType,
        NSNotEqualToPredicateOperatorType
    };
    NSPredicateOperatorType op = cp.predicateOperatorType;
    if (op >= NSMatchesPredicateOperatorType)
        return nil; // don't know how to flip this or it's unflippable
    return [[NSComparisonPredicate alloc] initWithLeftExpression: cp.rightExpression
                                                 rightExpression: cp.leftExpression
                                                        modifier: cp.comparisonPredicateModifier
                                                            type: kFlipped[op]
                                                         options: cp.options];
}


#define SWAP(A, B) {__typeof(A) temp = (A); (A) = (B); (B) = temp;}


// If the two predicates can be merged with an AND, returns the merged form; else returns nil.
// Assumes the LHS of each is non-variable, while the RHS is variable.
static NSComparisonPredicate* mergeComparisons(NSComparisonPredicate* p1,
                                               NSComparisonPredicate* p2)
{
    // Preliminary checks:
    if ([p1 isEqual: p2])
        return p1;
    NSExpression* lhs = p1.leftExpression;
    if (![lhs isEqual: p2.leftExpression])
        return nil;     // LHS must match
    NSPredicateOperatorType op1 = p1.predicateOperatorType;
    NSPredicateOperatorType op2 = p2.predicateOperatorType;
    if (op1 == op2)
        return nil;     // Can't combine two of the same comparison (a < b and a < c)
    if (op1 > op2) {    // Sort operators so op1 comes before op2
        SWAP(op1, op2);
        SWAP(p1, p2);
    }

    // Combine a <= and a >= into a 'between':
    if (op1 == NSLessThanOrEqualToPredicateOperatorType &&
            op2 == NSGreaterThanOrEqualToPredicateOperatorType) {
        NSExpression* range = [NSExpression expressionForAggregate: @[p2.rightExpression,
                                                                      p1.rightExpression]];
        return (NSComparisonPredicate *) [NSComparisonPredicate predicateWithLeftExpression: lhs
                                                  rightExpression: range
                                                         modifier: p1.comparisonPredicateModifier
                                                             type: NSBetweenPredicateOperatorType
                                                          options: p1.options];
    }
    return nil;
}


// Turns an NSArray of NSExpressions into either nil, the single expression if there's only one,
// or an aggregate (tuple) expression.
static NSExpression* combineExpressions(NSArray* expressions) {
    switch (expressions.count) {
        case 0:     return nil;
        case 1:     return expressions[0];
        default:    return [NSExpression expressionForAggregate: expressions];
    }
}


@end


#if 0
static void dumpExpression(NSExpression* exp, NSString* indent) {
    Log(@"%@%@", indent, exp);
}

static void dumpPredicate(NSPredicate* pred, NSString* indent) {
    NSString* deeper = [indent stringByAppendingString: @"    "];
    if ([pred isKindOfClass: [NSComparisonPredicate class]]) {
        NSComparisonPredicate* cp = (NSComparisonPredicate*)pred;
        dumpExpression(cp.leftExpression, deeper);
        Log(@"%@comparison (%lu)", indent, cp.predicateOperatorType);
        dumpExpression(cp.rightExpression, deeper);
    } else if ([pred isKindOfClass: [NSCompoundPredicate class]]) {
        NSCompoundPredicate* cp = (NSCompoundPredicate*)pred;
        BOOL first = YES;
        for (NSPredicate* sub in cp.subpredicates) {
            if (first)
                first = NO;
            else
                Log(@"%@compound (%lu)", indent, cp.compoundPredicateType);
            dumpPredicate(sub, deeper);
        }
    } else {
        Log(@"%@??? %@", indent, pred);
    }
}
#endif
