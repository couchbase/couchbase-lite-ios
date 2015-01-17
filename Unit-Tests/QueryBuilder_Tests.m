//
//  QueryBuilder_Tests.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/22/14.
//
//

#import "CBLTestCase.h"
#import "CBLQueryBuilder+Private.h"


@interface QueryBuilder_Tests : CBLTestCaseWithDB
@end


@implementation QueryBuilder_Tests


// compact description of an object using "[a, b...]" for arrays and single-quoting strings.
static NSString* desc(id obj) {
    if ([obj isKindOfClass: [NSArray class]]) {
        NSMutableString* result = [@"[" mutableCopy];
        BOOL first = YES;
        for (id item in obj) {
            if (first)
                first = NO;
            else
                [result appendString: @", "];
            [result appendString: desc(item)];
        }
        [result appendString: @"]"];
        return result;
    } else if ([obj isKindOfClass: [NSString class]]) {
        return [NSString stringWithFormat: @"'%@'", obj];
    } else {
        return [obj description];
    }
}


// Checks whether desc(value) matches expectedDesc.
static BOOL matchDesc(NSString* what, id value, NSString* expectedDesc) {
    if([desc(value) isEqualToString: expectedDesc] || (!value && !expectedDesc))
        return YES;
    Log(@"  **EXPECTED %@", expectedDesc);
    return NO;
}


static void test(QueryBuilder_Tests *self,
                 NSArray* select,
                 NSString* where,
                 NSString* orderKey,
                 NSString* expectedMapPred,
                 NSString* expectedKeyExprs,
                 NSString* expectedValues,
                 NSString* expectedStartKey,
                 NSString* expectedEndKey,
                 NSString* expectedKeys,
                 NSString* expectedSorts,
                 NSString* expectedFilter)
{
    NSPredicate* wherePred = [NSPredicate predicateWithFormat: where];
    NSArray* orderBy = nil;
    if (orderKey) {
        orderBy = @[orderKey];
        //orderBy = @[[NSSortDescriptor sortDescriptorWithKey: orderKey ascending: YES]];
    }
    Log(@"--------------");
    Log(@"Select: %@", desc(select));
    Log(@"Where:  %@", wherePred);
    Log(@"Order:  %@", orderKey);
    NSError* error;
    CBLQueryBuilder* builder = [[CBLQueryBuilder alloc] initWithDatabase: nil
                                                                  select: select
                                                                   where: where
                                                                 orderBy: orderBy
                                                                   error: &error];
    Assert(builder, @"Couldn't create query builder: %@", error);
    Log(@"Explanation:\n%@", builder.explanation);
    BOOL result = YES;
    Log(@"Map pred --> %@", builder.mapPredicate);
    result = matchDesc(@"mapPredicate", builder.mapPredicate, expectedMapPred) && result;
    Log(@"Key expr --> %@", desc(builder.keyExpression));
    result = matchDesc(@"keyExpression", builder.keyExpression, expectedKeyExprs) && result;
    Log(@"Value -->    %@", desc(builder.valueExpression));
    result = matchDesc(@"valueExpression", builder.valueExpression, expectedValues) && result;
    Log(@"StartKey --> %@", desc(builder.queryStartKey));
    result = matchDesc(@"queryStartKey", builder.queryStartKey, expectedStartKey) && result;
    Log(@"EndKey -->   %@", desc(builder.queryEndKey));
    result = matchDesc(@"queryEndKey", builder.queryEndKey, expectedEndKey) && result;
    Log(@"Keys -->     %@", desc(builder.queryKeys));
    result = matchDesc(@"queryKeys", builder.queryKeys, expectedKeys) && result;
    Log(@"Sort -->     %@", desc(builder.sortDescriptors));
    result = matchDesc(@"sortDescriptors", builder.sortDescriptors, expectedSorts) && result;
    Log(@"Filter -->   %@", builder.filter);
    result = matchDesc(@"filter", builder.filter, expectedFilter) && result;

    Assert(result, @"Incorrect query builder");
    Log(@"**OK**");
}


- (void) test00_Plan {
    test(self, /*select*/ @[@"wingspan"],
         /*where*/ @"name in $NAMES",
         /*order by*/ @"name",
         nil,
         @"name",
         @"wingspan",
         nil,
         nil,
         @"$NAMES", // .keys
         nil,
         nil);

    test(self, /*select*/ @[@"firstName", @"lastName"],
         /*where*/ @"firstName ==[c] $F",
         /*order by*/ nil,
         nil,
         @"lowercase:(firstName)",
         @"{firstName, lastName}",
         @"lowercase:($F)",
         @"lowercase:($F)",
         nil,
         nil,
         nil);

    test(self, /*select*/ @[@"title", @"body", @"author", @"date"],
         /*where*/ @"type == 'post' and title beginswith[c] $PREFIX and tags contains $TAG",
         /*order by*/ @"date",
         @"type == \"post\"",
         @"{tags, lowercase:(title)}",
         @"{title, body, author, date}",
         @"{$TAG, lowercase:($PREFIX)}",
         @"{$TAG, lowercase:($PREFIX)}",
         nil,
         @"[(value3, ascending, compare:)]",
         nil);

    test(self, /*select*/ @[@"title", @"body", @"author", @"date"],
         /*where*/ @"type == 'post' and tags contains $TAG",
         /*order by*/ nil,
         @"type == \"post\"",
         @"tags",
         @"{title, body, author, date}",
         @"$TAG",
         @"$TAG",
         nil,
         nil,
         nil);

    test(self, /*select*/ @[@"title", @"body", @"author", @"date"],
         /*where*/ @"type == 'post' and tags contains $TAG",
         /*order by*/ @"date",
         @"type == \"post\"",
         @"{tags, date}",
         @"{title, body, author}",
         @"{$TAG}",
         @"{$TAG}",
         nil,
         nil,
         nil);
    
    test(self, /*select*/ @[@"body", @"author", @"date"],
         /*where*/ @"type == 'comment' and post_id == $POST_ID",
         /*order by*/ @"date",
         @"type == \"comment\"",
         @"{post_id, date}",
         @"{body, author}",
         @"{$POST_ID}",
         @"{$POST_ID}",
         nil,
         nil,
         nil);

    test(self, /*select*/ @[@"wingspan", @"name"],
         /*where*/ @"type == 'bird'",
         /*order by*/ @"name",
         @"type == \"bird\"",
         @"name",
         @"wingspan",
         nil, // there's no startKey or endKey because we didn't specify a range.
         nil,
         nil,
         nil,
         nil);

    test(self, /*select*/ @[@"Album"],
         /*where*/ @"TotalTime / 1000.0 between {$MIN, $MAX} and Artist = $A and Name contains $NAME",
         /*order by*/ @"Name",
         nil,
         @"{Artist, TotalTime / 1000}",
         @"{Album, Name}",
         @"{$A, $MIN}",
         @"{$A, $MAX}",
         nil,
         @"[(value1, ascending, compare:)]",
         @"value1 CONTAINS $NAME");

    test(self, /*select*/ @[@"Album"],
         /*where*/ @"Time >= $MIN and Time <= $MAX and Artist = $A and Name contains $NAME",
         /*order by*/ @"Name",
         nil,
         @"{Artist, Time}",
         @"{Album, Name}",
         @"{$A, $MIN}",
         @"{$A, $MAX}",
         nil,
         @"[(value1, ascending, compare:)]",
         @"value1 CONTAINS $NAME");

    test(self, /*select*/ @[@"count"],
         /*where*/ @"type == 'foo' or type == 'bar'", // OR is legal if args are not variable
         /*order by*/ @"date",
         @"type == \"foo\" OR type == \"bar\"",
         @"date",
         @"count",
         nil,
         nil,
         nil,
         nil,
         nil);
}


- (void) test00_IllegalPredicates {
    NSArray* preds = @[ @"price + $DELTA < 100",
                        @"color = $COLOR or color = $OTHER_COLOR",
                        ];
    for (NSString* pred in preds) {
        NSError* error;
        CBLQueryBuilder* b = [[CBLQueryBuilder alloc] initWithDatabase: nil
                                                                select: nil where: pred
                                                               orderBy: nil error: &error];
        if (b)
            Log(@"Failed to reject; explanation:\n%@", b.explanation);
        Assert(b == nil, @"Illegal predicate was accepted: %@", pred);
        Log(@"Rejected %@  --  %@", pred, error.localizedFailureReason);
    }
}


- (void) test00_ViewGeneration {
    NSError* error;
    CBLQueryBuilder* p1 = [[CBLQueryBuilder alloc] initWithDatabase: db
                                                             select: @[@"wingspan"]
                                                              where: @"name in $NAMES"
                                                            orderBy: nil
                                                              error: &error];
    Assert(p1);
    Log(@"Explanation: %@", p1.explanation);
//TEMP    AssertEqual(p1.view.name, @"builder-IGPag5AW7YUwzzQqgOoqPzyiXGc=");

    CBLQueryBuilder* p2 = [[CBLQueryBuilder alloc] initWithDatabase: db
                                                             select: @[@"wingspan"]
                                                              where: @"name >= $NAME1"
                                                            orderBy: nil
                                                              error: &error];
    Assert(p2);
    Log(@"Explanation: %@", p2.explanation);
//TEMP    AssertEqual(p2.view.name, @"builder-IGPag5AW7YUwzzQqgOoqPzyiXGc=");
    AssertEq(p2.view, p1.view);
}


- (void) test00_Explanation {
    NSError* error;
    CBLQueryBuilder* b = [[CBLQueryBuilder alloc]
                            initWithDatabase: db
                            select: @[@"title", @"body", @"author", @"date"]
                            where: @"type == 'post' and tags contains $TAG"
                            orderBy: @[@"-date"]
                            error: &error];
    NSString* exp = b.explanation;
    Log(@"Explanation = \n%@", exp);
#if 0 //TEMP
    AssertEqual(exp,
@"// view \"builder-NCAd2nwidQmv6GjOVGB+tZ8Wflw=\":\n\
view.map = {\n\
    if (type == \"post\")\n\
        for (i in tags)\n\
            emit([i, date], [title, body, author]);\n\
};\n\
query.startKey = [$TAG];\n\
query.endKey = [$TAG];\n\
query.prefixMatchLevel = 1;\n");
#endif
}


- (void) test00_StringIn {
    [self createDocuments: 100];

    NSError* error;
    CBLQueryBuilder* b = [[CBLQueryBuilder alloc] initWithDatabase: db
                                                            select: nil
                                                             where: @"$PATTERN in _id"
                                                           orderBy: nil
                                                             error: &error];
    Assert(b, @"Failed to build: %@", error);
    Log(@"%@", b.explanation);

    CBLQueryEnumerator* e = [b runQueryWithContext: @{@"PATTERN": @"AA"} error: &error];
    Assert(e, @"Query failed: %@", error);
    for (CBLQueryRow* row in e) {
        Assert([row.documentID rangeOfString: @"AA"].length > 0);
    }
}


- (void) test00_Reduce {
    [self createDocuments: 100];

    NSError* error;
    NSExpression* sum = [NSExpression expressionWithFormat: @"median(sequence)"];
    CBLQueryBuilder* b = [[CBLQueryBuilder alloc] initWithDatabase: db
                                                            select: @[sum]
                                                             where: @"testName=='testDatabase'"
                                                           orderBy: nil
                                                             error: &error];
    Assert(b, @"Failed to build: %@", error);
    Log(@"%@", b.explanation);

    CBLQuery* query = [b createQueryWithContext: nil];
    CBLQueryRow* row = [[query run: &error] nextObject];
    Assert(row, @"Query failed: %@", error);
    Log(@"%@", row);
    AssertEqual(row.value, @(49.5));
}


@end
