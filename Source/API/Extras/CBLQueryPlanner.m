//
//  CBLQueryPlanner.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 8/4/14.
//
//

#import "CBLQueryPlanner.h"
#import "CBLQueryPlanner+Private.h"
#import <CouchbaseLite/CouchbaseLite.h>
#import <CommonCrypto/CommonDigest.h>


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



// Standalone equivalents of stuff from MYUtilities:
#ifndef $cast
#define $cast(CLASSNAME,OBJ)    ((CLASSNAME*)(_cast([CLASSNAME class],(OBJ))))
#define $castIf(CLASSNAME,OBJ)  ((CLASSNAME*)(_castIf([CLASSNAME class],(OBJ))))
static inline id _cast(Class requiredClass, id object) {
    NSCAssert([object isKindOfClass: requiredClass], @"Value is %@, not %@",
              [object class], requiredClass);
    return object;
}
static inline id _castIf(Class requiredClass, id object) {
    return [object isKindOfClass: requiredClass] ? object : nil;
}
#endif

#ifndef LogTo
#define LOGGING 1
#define LogTo(KEYWORD, FMT, ...)  if(!LOGGING) ; else NSLog(FMT, __VA_ARGS__)
#define Warn(FMT, ...)            NSLog(@"WARNING: " #FMT, __VA_ARGS__)
#endif

static NSArray* $map(NSArray* array, id (^block)(id obj)) {
    NSMutableArray* mapped = [[NSMutableArray alloc] initWithCapacity: array.count];
    for (id obj in array) {
        id mappedObj = block(obj);
        if (mappedObj)
            [mapped addObject: mappedObj];
    }
    return [mapped copy];
}

static NSData* SHA1Digest(NSData* input) {
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(input.bytes, (CC_LONG)input.length, digest);
    return [NSData dataWithBytes: &digest length: sizeof(digest)];
}


@implementation CBLQueryPlanner
{
    // These are only used during initialization:
    NSComparisonPredicate* _equalityKey;    // Predicate with equality test, used as key
    NSComparisonPredicate* _otherKey;       // Other predicate used as key
    NSArray* _keyPredicates;                // Predicates whose LHS generate the key, at map time
    NSArray* _valueTemplate;                // Values desired
    BOOL _explodeKey;                       // Emit each item of key separately?
    NSMutableArray* _filterPredicates;      // Predicates to go into _queryFilter
    NSError* _error;                        // Set during -scanPredicate: if predicate is invalid

    // These will be used to initialize queries:
    NSExpression* _queryStartKey;           // The startKey to use in queries
    NSExpression* _queryEndKey;             // The endKey to use in queries
    NSExpression* _queryKeys;               // The 'keys' array to use in queries
    BOOL _queryInclusiveStart, _queryInclusiveEnd;  // The inclusiveStart/End to use in queries
    NSPredicate* _queryFilter;              // Postprocessing filter predicate to use in the query
    NSArray* _querySort;                    // Sort descriptors for the query

    // Used for -explanation
    NSPredicate* _mapPredicate;
}

@synthesize view=_view;

#if DEBUG // allow unit tests to inspect these internal properties
@synthesize mapPredicate=_mapPredicate, sortDescriptors=_querySort, filter=_queryFilter,
            queryStartKey=_queryStartKey, queryEndKey=_queryEndKey, queryKeys=_queryKeys,
            queryInclusiveStart=_queryInclusiveStart, queryInclusiveEnd=_queryInclusiveEnd;
#endif


- (instancetype) initWithView: (CBLView*)view
                       select: (NSArray*)valueTemplate
               wherePredicate: (NSPredicate*)predicate
                      orderBy: (NSArray*)sortDescriptors
                        error: (NSError**)outError
{
    self = [super init];
    if (self) {
        _view = view;
        _valueTemplate = valueTemplate;
        _querySort = sortDescriptors;

        // Scan the input:
        NSPredicate* mapPredicate = [self scanPredicate: predicate];
        _mapPredicate = mapPredicate;
        if (_error) {
            if (outError)
                *outError = _error;
            return nil;
        }

        _keyPredicates = [self createKeyPredicates];
        _querySort = [self createQuerySortDescriptors];
        _queryFilter = [self createQueryFilter];

        // If the predicate contains a "property CONTAINS $item" test, then we should emit every
        // item of the 'property' array as a separate key during the map phase.
        _explodeKey = (_equalityKey.predicateOperatorType == NSContainsPredicateOperatorType);

        if (_view) {
            [[self class] defineView: _view
                    withMapPredicate: mapPredicate
                       keyExpression: self.keyExpression
                          explodeKey: _explodeKey
                     valueExpression: self.valueExpression];
        }

        [self precomputeQuery];

        LogTo(View, @"Created CBLQueryPlanner on %@:\n%@", view, self.explanation);
    }
    return self;
}


- (instancetype) initWithView: (CBLView*)view
                       select: (NSArray*)valueTemplate
                        where: (NSString*)predicate
                      orderBy: (NSArray*)sortDescriptors
                        error: (NSError**)outError
{
    return [self initWithView: view
                       select: valueTemplate
               wherePredicate: [NSPredicate predicateWithFormat: predicate argumentArray: nil]
                      orderBy: sortDescriptors
                        error: outError];
}


- (NSString*) explanation {
    NSMutableString* out = [@"view.map = {\n" mutableCopy];
    if (_mapPredicate)
        [out appendFormat: @"    if (%@)\n    ", _mapPredicate];
    if (_explodeKey) {
        NSExpression* keyExpression = self.keyExpression;
        if (keyExpression.expressionType != NSAggregateExpressionType) {
            // looping over simple key:
            [out appendFormat: @"    for (i in %@)\n", keyExpression];
            if (_mapPredicate)
                [out appendString: @"    "];
            [out appendFormat: @"        emit(i, %@);\n};\n", self.valueExpression];
        } else {
            // looping over compound key:
            NSArray* keys = keyExpression.collection;
            [out appendFormat: @"    for (i in %@)\n", keys[0]];
            if (_mapPredicate)
                [out appendString: @"    "];
            NSArray* restOfKey = [keys subarrayWithRange: NSMakeRange(1, keys.count-1)];
            [out appendFormat: @"        emit({i, %@}, %@);\n};\n",
                 [restOfKey componentsJoinedByString: @", "], self.valueExpression];
        }
    } else {
        [out appendFormat: @"    emit(%@, %@);\n};\n", self.keyExpression, self.valueExpression];
    }

    if (_queryKeys)
        [out appendFormat: @"query.keys = %@;\n", _queryKeys];
    if (_queryStartKey)
        [out appendFormat: @"query.startKey = %@;\n", _queryStartKey];
    if (!_queryInclusiveStart)
        [out appendFormat: @"query.inclusiveStart = NO;\n"];
    if (_queryEndKey) {
        [out appendFormat: @"query.endKey = %@", _queryEndKey];
        if (_otherKey.predicateOperatorType == NSBeginsWithPredicateOperatorType)
            [out appendString: @"+\"\\uFFFE\""];
        [out appendFormat: @";\n"];
    }
    if (!_queryInclusiveEnd)
        [out appendFormat: @"query.inclusiveEnd = NO;\n"];
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
- (NSPredicate*) scanPredicate: (NSPredicate*)pred {
    if ([pred isKindOfClass: [NSComparisonPredicate class]]) {
        // Comparison of expressions, e.g. "a < b":
        NSComparisonPredicate* cp = (NSComparisonPredicate*)pred;
        BOOL lhsIsVariable = [self expressionUsesVariable: cp.leftExpression];
        BOOL rhsIsVariable = [self expressionUsesVariable: cp.rightExpression];
        if (!lhsIsVariable && !rhsIsVariable)
            return cp;

        // Comparison involves a variable, so save variable expression as a key:
        if (lhsIsVariable) {
            if (rhsIsVariable) {
                [self fail: @"Both sides can't be variable: %@", pred];
                return nil;
            }
            cp = flipComparison(cp); // Always put variable on RHS
        }
        [self addKeyPredicate: cp];
        // Result of this comparison is unknown at indexing time, so return nil:
        return nil;

    } else if ([pred isKindOfClass: [NSCompoundPredicate class]]) {
        // Logical compound of sub-predicates, e.g. "a AND b AND c":
        NSCompoundPredicate* cp = (NSCompoundPredicate*)pred;
        if (cp.compoundPredicateType != NSAndPredicateType) {
            [self fail: @"Sorry, the OR and NOT operators aren't supported yet"];
            return nil;
        }
        NSMutableArray* subpredicates = [NSMutableArray array];
        for (NSPredicate* sub in cp.subpredicates) {
            NSPredicate* scanned = [self scanPredicate: sub];  // Recurse!!
            if (scanned)
                [subpredicates addObject: scanned];
        }
        if (subpredicates.count == 0)
            return nil;                 // all terms are unknown, so return unknown
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
    if (!_filterPredicates)
        _filterPredicates = [NSMutableArray array];
    [_filterPredicates addObject: cp];
    return NO;
}


// Returns YES if an NSExpression's value involves evaluating a variable.
- (BOOL) expressionUsesVariable: (NSExpression*)expression {
    switch (expression.expressionType) {
        case NSVariableExpressionType:
            return YES;
        case NSFunctionExpressionType:
            for (NSExpression* expr in expression.arguments)
                if ([self expressionUsesVariable: expr])
                    return YES;
            return NO;
        case NSUnionSetExpressionType:
        case NSIntersectSetExpressionType:
        case NSMinusSetExpressionType:
            return [self expressionUsesVariable: expression.leftExpression]
                || [self expressionUsesVariable: expression.rightExpression];
        case NSAggregateExpressionType:
            for (NSExpression* expr in expression.collection)
                if ([self expressionUsesVariable: expr])
                    return YES;
            return NO;
        case NSConstantValueExpressionType:
        case NSEvaluatedObjectExpressionType:
        case NSKeyPathExpressionType:
        case NSAnyKeyExpressionType:
            return NO;
        default:
            [self fail: @"Unsupported expression type %d: %@",
                   (int)expression.expressionType, expression];
            return NO;
    }
}


#pragma mark - FILTER PREDICATE & SORT DESCRIPTORS:


- (NSPredicate*) createQueryFilter {
    // Update each of _filterPredicates to make its keypath relative to the query rows' values.
    for (NSUInteger i = 0; i < _filterPredicates.count; ++i) {
        NSComparisonPredicate* cp = _filterPredicates[i];
        NSExpression* lhs = [self rewriteKeyPathsInExpression: cp.leftExpression];
        cp = [[NSComparisonPredicate alloc] initWithLeftExpression: lhs
                                                   rightExpression: cp.rightExpression
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
    else {
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
    return aggregateExpressions($map(_keyPredicates, ^id(NSComparisonPredicate* cp) {
        NSExpression* expr = cp.leftExpression;
        if (cp.options & NSCaseInsensitivePredicateOption)
            expr = [NSExpression expressionForFunction: @"lowercase:" arguments: @[expr]];
        return expr;
    }));
}


// The expression that should be emitted as the value
- (NSExpression*) valueExpression {
    return aggregateExpressions($map(_valueTemplate, ^id(id item) {
        if (![item isKindOfClass: [NSExpression class]])
            item = [NSExpression expressionForKeyPath: $castIf(NSString, item)];
        return item;
    }));
}


// Sets the view's map block. (This is a class method to avoid having the block accidentally close
// over any instance variables, creating a reference cycle.)
+ (void) defineView: (CBLView*)view
   withMapPredicate: (NSPredicate*)mapPredicate
      keyExpression: (NSExpression*)keyExpression
         explodeKey: (BOOL)explodeKey
    valueExpression: (NSExpression*)valueExpr
{
    // Compute a map-block version string that's unique to this configuration:
    NSMutableDictionary* versioned = [NSMutableDictionary dictionary];
    versioned[@"keyExpression"] = keyExpression;
    if (mapPredicate)
        versioned[@"mapPredicate"] = mapPredicate;
    if (valueExpr)
        versioned[@"valueExpression"] = valueExpr;
    NSData* archive = [NSKeyedArchiver archivedDataWithRootObject: versioned];
    NSString* version = [CBLJSON base64StringWithData: SHA1Digest(archive)];

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
    } version: version];
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
                [endKey addObject: @{}];
                _queryInclusiveEnd = NO;
                break;
            case NSBeginsWithPredicateOperatorType:
                [startKey addObject: keyExpr];
                [endKey addObject: keyExpr];  // can't append \uFFFF until query time
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
        id startKey = [_queryStartKey expressionValueWithObject: nil
                                                        context: mutableContext];
        id endKey = [_queryEndKey expressionValueWithObject: nil
                                                    context: mutableContext];
        if (_otherKey.predicateOperatorType == NSBeginsWithPredicateOperatorType) {
            // The only way to do a prefix match is to make the endKey the startKey + a high character
            if ([endKey isKindOfClass: [NSArray class]]) {
                NSString* str = $cast(NSString, [startKey lastObject]);
                str = [str stringByAppendingString: @"\uFFFE"];
                NSMutableArray* newEnd = [endKey mutableCopy];
                [newEnd replaceObjectAtIndex: newEnd.count-1 withObject: str];
                endKey = newEnd;
            } else {
                endKey = [$cast(NSString, startKey) stringByAppendingString: @"\uFFFE"];
            }
        }

        query.startKey = startKey;
        query.endKey = endKey;
        query.inclusiveStart = _queryInclusiveStart;
        query.inclusiveEnd = _queryInclusiveEnd;
    }
    query.sortDescriptors = _querySort;
    query.postFilter = [_queryFilter predicateWithSubstitutionVariables: mutableContext];
    return query;
}


#pragma mark - UTILITIES:


- (void) fail: (NSString*)message, ... NS_FORMAT_FUNCTION(1,2) {
    if (!_error) {
        va_list args;
        va_start(args, message);
        message = [[NSString alloc] initWithFormat: message arguments: args];
        va_end(args);
        NSDictionary* userInfo = @{NSLocalizedFailureReasonErrorKey: message};
        _error = [NSError errorWithDomain: @"CBLQueryPlanner" code: -1 userInfo: userInfo];
    }
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


static NSExpression* aggregateExpressions(NSArray* expressions) {
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
