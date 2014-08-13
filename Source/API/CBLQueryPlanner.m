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


@implementation CBLQueryPlanner
{
    NSComparisonPredicate* _equalityKey;    // Predicate with equality test, used as key
    NSComparisonPredicate* _otherKey;       // Other predicate used as key
    NSArray* _keyExpressions;               // Expressions that generate the key, at map time
    NSExpression* _queryStartKey;
    NSExpression* _queryEndKey;
    BOOL _queryInclusiveStart, _queryInclusiveEnd;
    NSMutableArray* _filterPredicates;      // Predicates that have to run after the query runs
    NSError* _error;                        // Set during -scanPredicate: if predicate is invalid
}

@synthesize view=_view, mapPredicate=_mapPredicate, keyExpressions=_keyExpressions,
            valueTemplate=_valueTemplate, sortDescriptors=_sort, filter=_filter,
            queryStartKey=_queryStartKey, queryEndKey=_queryEndKey,
            queryInclusiveStart=_queryInclusiveStart, queryInclusiveEnd=_queryInclusiveEnd;


- (instancetype) initWithView: (CBLView*)view
                       select: (NSArray*)valueTemplate
                        where: (NSPredicate*)predicate
                      orderBy: (NSArray*)sortDescriptors
                        error: (NSError**)outError
{
    self = [super init];
    if (self) {
        // Scan the input:
        _view = view;
        _valueTemplate = valueTemplate;
        _sort = sortDescriptors;
        _mapPredicate = [self scanPredicate: predicate];
        if (_error) {
            if (outError)
                *outError = _error;
            return nil;
        }

        [self fixUpFilterPredicates];
        _keyExpressions = [self createKeyExpressions];
        _sort = [self createSortDescriptors: _sort];

        if (_filterPredicates.count == 1)
            _filter = _filterPredicates[0];
        else if (_filterPredicates.count > 0)
            _filter = [[NSCompoundPredicate alloc] initWithType: NSAndPredicateType
                                                  subpredicates: _filterPredicates];

        BOOL keyContains = (_equalityKey.predicateOperatorType == NSContainsPredicateOperatorType);

        if (_view) {
            [[self class] defineView: _view
                    withMapPredicate: _mapPredicate
                      keyExpressions: self.keyExpressions
               primaryKeyIsContainer: keyContains
                     valueProperties: _valueTemplate
                                sort: _sort];
        }

        [self precomputeQuery];
    }
    return self;
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
                          op == NSContainsPredicateOperatorType)) {
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
            [self fail: @"Unsupported expression type %ld: %@",
                   expression.expressionType, expression];
            return NO;
    }
}


#pragma mark - FILTER PREDICATE & SORT DESCRIPTORS:


// Updates each of _filterPredicates to make its keypaths relative to the query rows' values.
- (void) fixUpFilterPredicates {
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
            [self fail: @"Unsupported expression type %ld: %@",
             expression.expressionType, expression];
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
    for (NSExpression* keyExpr in _keyExpressions) {
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
- (NSArray*) createKeyExpressions {
    NSMutableArray* exprs = [NSMutableArray array];
    if (_equalityKey)
        [exprs addObject: _equalityKey.leftExpression];
    if (_otherKey)
        [exprs addObject: _otherKey.leftExpression];
    else {
        for (NSSortDescriptor* sortDesc in _sort)
            [exprs addObject: [NSExpression expressionForKeyPath: sortDesc.key]];
    }

    // Remove redundant values that are already part of the key:
    NSMutableArray* values = [_valueTemplate mutableCopy];
    for (NSExpression* expr in exprs) {
        if (expr.expressionType == NSKeyPathExpressionType) {
            [values removeObject: expr];
            [values removeObject: expr.keyPath];
        }
    }
    _valueTemplate = [values copy];

    return exprs;
}


// Computes the post-processing sort descriptors to be applied after the query runs.
- (NSArray*) createSortDescriptors: (NSArray*)inputSort {
    if (inputSort.count == 0 || !_otherKey)
        return nil;

    NSMutableArray* sort = [NSMutableArray arrayWithCapacity: inputSort.count];
    for (NSSortDescriptor* sd in inputSort) {
        [sort addObject: [[NSSortDescriptor alloc] initWithKey: [self rewriteKeyPath: sd.key]
                                                     ascending: sd.ascending
                                                      selector: sd.selector]];
    }
    return sort;
}


#pragma mark - DEFINING THE VIEW:


// Sets the view's map block. (This is a class method to avoid having the block accidentally close
// over any instance variables, creating a reference cycle.)
+ (void) defineView: (CBLView*)view
   withMapPredicate: (NSPredicate*)mapPredicate
     keyExpressions: (NSArray*)keyExpressions
primaryKeyIsContainer: (BOOL)primaryKeyIsContainer
    valueProperties: (NSArray*)valueTemplate
               sort: (NSArray*)sort
{
    // Compute a map-block version string that's unique to this configuration:
    NSMutableDictionary* versioned = [NSMutableDictionary dictionary];
    versioned[@"keyExpressions"] = keyExpressions;
    if (mapPredicate)
        versioned[@"mapPredicate"] = mapPredicate;
    if (valueTemplate)
        versioned[@"valueTemplate"] = valueTemplate;
    NSData* archive = [NSKeyedArchiver archivedDataWithRootObject: versioned];
    NSString* version = [CBLJSON base64StringWithData: CBLSHA1Digest(archive)];

    id singleValueTemplate = nil;
    if (valueTemplate.count == 1)
        singleValueTemplate = valueTemplate[0];
    NSUInteger numKeys = keyExpressions.count;

    // Define the view's map block:
    [view setMapBlock: ^(NSDictionary *doc, CBLMapEmitBlock emit) {
        if (!mapPredicate || [mapPredicate evaluateWithObject: doc]) {  // check mapPredicate
            id value = nil;
            if (singleValueTemplate) {
                value = getValue(doc, singleValueTemplate);
            } else {
                value = [NSMutableArray array];
                for (id property in valueTemplate) {
                    id v = getValue(doc, property) ?: [NSNull null];
                    [value addObject: v];
                }
            }

            if (numKeys == 1) {
                // Single key:
                id key = [keyExpressions[0] expressionValueWithObject: doc context: nil];
                if (primaryKeyIsContainer && [key isKindOfClass: [NSArray class]]) {
                    for (id keyItem in key)
                        emit(keyItem, value);
                } else if (key != nil) {
                    emit(key, value);
                }
            } else {
                NSMutableArray* key = [[NSMutableArray alloc] initWithCapacity: numKeys];
                for (NSExpression* keyExpression in keyExpressions) {
                    id keyItem = [keyExpression expressionValueWithObject: doc context: nil];
                    if (!keyItem)
                        return; // Missing property so can't emit anything
                    //FIX: What if keyItem is an array? Emit multiple times??
                    [key addObject: keyItem];
                }
                emit(key, value);
            }
        }
    } version: version];
}


#pragma mark - QUERYING:


// Creates the query startKey/endKey expressions and the inclusive start/end values.
// This is called at initialization time only.
- (BOOL) precomputeQuery {
    _queryInclusiveStart = _queryInclusiveEnd = YES;
    NSMutableArray* startKey = [NSMutableArray array];
    NSMutableArray* endKey   = [NSMutableArray array];

    if (_equalityKey) {
        // The LHS is the expression emitted as the view's key, and the RHS is a variable
        NSExpression* keyExpr = _equalityKey.rightExpression;
        [startKey addObject: keyExpr];
        [endKey   addObject: keyExpr];
    }

    if (_otherKey) {
        NSExpression* keyExpr = _otherKey.rightExpression;
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

    if (_keyExpressions.count > 1) {
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
    query.sortDescriptors = _sort;
    query.postFilter = [_filter predicateWithSubstitutionVariables: mutableContext];
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


// Evaluates expr against doc, where expr is either a key-path or an expression.
static id getValue(NSDictionary* doc, id expr) {
    if ([expr isKindOfClass: [NSString class]])
        return [doc valueForKeyPath: expr];
    else if (expr) // assumed to be NSExpression
        return [expr expressionValueWithObject: doc context: nil];
    else
        return nil;
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
        return [NSComparisonPredicate predicateWithLeftExpression: lhs
                                                  rightExpression: range
                                                         modifier: p1.comparisonPredicateModifier
                                                             type: NSBetweenPredicateOperatorType
                                                          options: p1.options];
    }
    return nil;
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
