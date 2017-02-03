//
//  QueryTest.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/13/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLTestCase.h"
#import "CBLQuery+Internal.h"
#import "CBLInternal.h"


@interface QueryTest : CBLTestCase

@end


@implementation QueryTest


- (uint64_t) verifyQuery: (CBLQuery*)q test: (void (^)(uint64_t n, CBLQueryRow *row))block {
    NSError* error;
    NSEnumerator* e = [q run: &error];
    Assert(e, @"Query failed: %@", error);
    uint64_t n = 0;
    for (CBLQueryRow *row in e) {
        NSLog(@"Row: docID='%@', sequence=%llu", row.documentID, row.sequence);
        block(++n, row);
    }
    return n;
}


- (void) test01_Predicates {
    // The query with the 'matches' operator requires there to be a FTS index on 'blurb':
    NSError* error;
    Assert([_db createIndexOn: @[@"blurb"] type: kCBLFullTextIndex options: NULL error: &error]);
    
    const struct {const char *pred; const char *json5;} kTests[] = {
        {"nickname == 'Bobo'",      "{WHERE: ['=', ['.nickname'],'Bobo']}"},
        {"name.first == $FIRSTNAME","{WHERE: ['=', ['.name.first'],['$FIRSTNAME']]}"},
        {"ALL children.age < 18",   "{WHERE: ['EVERY','X',['.children'],['<',['?X','age'], 18]]}"},
        {"ANY children == 'Bobo'",  "{WHERE: ['ANY', 'X', ['.children'], ['=', ['?X'], 'Bobo']]}"},
        {"'Bobo' in children",      "{WHERE: ['ANY', 'X', ['.children'], ['=', ['?X'], 'Bobo']]}"},
        {"name in $NAMES",          "{WHERE: ['IN', ['.name'], ['$NAMES']]}"},
        {"blurb matches 'N1QL SQLite'","{WHERE: ['MATCH', ['.blurb'], 'N1QL SQLite']}"},
        {"fruit contains 'ran'",    "{WHERE: ['CONTAINS()', ['.fruit'], 'ran']}"},
        {"age between {13, 19}",    "{WHERE: ['BETWEEN', ['.age'], 13, 19]}"},
        {"coords[0] < 90",          "{WHERE: ['<', ['.coords[0]'], 90]}"},
        {"coords[FIRST] < 90",      "{WHERE: ['<', ['.coords[0]'], 90]}"},
        {"coords[LAST] < 180",      "{WHERE: ['<', ['.coords[-1]'], 180]}"},
        {"coords[SIZE] == 2",       "{WHERE: ['=', ['ARRAY_COUNT()', ['.coords']], 2]}"},
        {"lowercase(name) == 'bobo'","{WHERE: ['=', ['LOWER()', ['.name']], 'bobo']}"},
        {"name ==[c] 'Bobo'",       "{WHERE: ['=', ['LOWER()', ['.name']], ['LOWER()', 'Bobo']]}"},
        {"sum(prices) > 100",       "{WHERE: ['>', ['ARRAY_SUM()', ['.prices']], 100]}"},
        {"age + 10 == 62",          "{WHERE: ['=', ['+', ['.age'], 10], 62]}"},
        {"foo + 'bar' == 'foobar'", "{WHERE: ['=', ['||', ['.foo'], 'bar'], 'foobar']}"},
        {"FUNCTION(email, 'REGEXP_LIKE', '.+@.+') == true",
                                    "{WHERE: ['=', ['REGEXP_LIKE()', ['.email'], '.+@.+'], true]}"},
    };
    for (unsigned i = 0; i < sizeof(kTests)/sizeof(kTests[0]); ++i) {
        NSString* pred = @(kTests[i].pred);
        //[CBLQuery dumpPredicate: [NSPredicate predicateWithFormat: pred argumentArray: nil]];
        NSString* expectedJson = [CBLQuery json5ToJSON: kTests[i].json5];
        CBLQuery* query = [self.db createQueryWhere: pred];
        query.orderBy = nil; // ignore ordering in this test
        NSData* actual = [query encodeAsJSON: &error];
        Assert(actual, @"Encode failed: %@", error);
        NSString* actualJSON = [[NSString alloc] initWithData: actual encoding: NSUTF8StringEncoding];
        AssertEqualObjects(actualJSON, expectedJson);

        Assert([query check: &error], @"Couldn't compile CBLQuery: %@", error);
    }
}


- (void) test02_NoWhereQuery {
    [self loadJSONResource: @"names_100"];
    NSError *error;
    // This is an all-docs query since it doesn't specify any criteria:
    CBLQuery* q = [self.db createQueryWhere: nil];
    Assert(q, @"Couldn't create query: %@", error);
    uint64_t numRows = [self verifyQuery: q test:^(uint64_t n, CBLQueryRow *row) {
        NSString* expectedID = [NSString stringWithFormat: @"doc-%03llu", n];
        AssertEqualObjects(row.documentID, expectedID);
        AssertEqual(row.sequence, n);
        CBLDocument* doc = row.document;
        AssertEqualObjects(doc.documentID, expectedID);
        AssertEqual(doc.sequence, n);
    }];
    AssertEqual(numRows, 100llu);
}


- (void) test02_AllDocsQuery {
    [self loadJSONResource: @"names_100"];
    uint64_t n = 0;
    for (CBLDocument* doc in self.db.allDocuments) {
        ++n;
        NSString* expectedID = [NSString stringWithFormat: @"doc-%03llu", n];
        AssertEqualObjects(doc.documentID, expectedID);
        AssertEqual(doc.sequence, n);
    }
    AssertEqual(n, 100llu);
}


- (void) test03_PropertyQuery               {[self propertyQueryWithReopen: NO];}
- (void) test03_PropertyQueryAfterReopen    {[self propertyQueryWithReopen: YES];}

- (void) propertyQueryWithReopen: (BOOL)reopen {
    [self loadJSONResource: @"names_100"];
    if (reopen)
        [self reopenDB];

    // Try a query involving a property. The first pass will be unindexed, the 2nd indexed.
    NSError *error;
    NSArray* indexSpec = @[ [NSExpression expressionForKeyPath: @"name.first"] ];
    for (int pass = 0; pass < 2; ++pass) {
        NSLog(@"---- Pass %d", pass);
        CBLQuery *q = [self.db createQueryWhere: @"name.first == $FIRSTNAME"];
        Assert(q, @"Couldn't create query: %@", error);
        NSString* explain = [q explain: &error];
        Assert(explain, @"-explain failed: %@", error);
        fprintf(stderr, "%s\n", explain.UTF8String);
        q.parameters = @{@"FIRSTNAME": @"Claude"};
        uint64_t numRows = [self verifyQuery: q test:^(uint64_t n, CBLQueryRow *row) {
            AssertEqualObjects(row.documentID, @"doc-009");
            AssertEqual(row.sequence, 9llu);
            CBLDocument* doc = row.document;
            AssertEqualObjects(doc.documentID, @"doc-009");
            AssertEqual(doc.sequence, 9llu);
            AssertEqualObjects([doc[@"name"] objectForKey: @"first"], @"Claude");
        }];
        AssertEqual(numRows, 1llu);

        if (pass == 0) {
            Assert([self.db createIndexOn: indexSpec type: kCBLValueIndex options: NULL error: &error]);
        }
    }
    Assert([self.db deleteIndexOn: indexSpec type: kCBLValueIndex error: &error]);
}


- (void) test04_Projection {
    NSArray* expectedDocs = @[@"doc-076", @"doc-008", @"doc-014"];
    NSArray* expectedZips = @[@"55587", @"56307", @"56308"];
    NSArray* expectedEmails = @[ @[@"monte.mihlfeld@nosql-matters.org"],
                                 @[@"jennefer.menning@nosql-matters.org", @"jennefer@nosql-matters.org"],
                                 @[@"stephen.jakovac@nosql-matters.org"] ];

    [self loadJSONResource: @"names_100"];
    CBLQuery *q = [self.db createQueryWhere: @"contact.address.state == $STATE"];
    q.orderBy = @[@"contact.address.zip"];
    q.returning = @[@"contact.address.zip", @"contact.email"];
    q.parameters = @{@"STATE": @"MN"};
    uint64_t numRows = [self verifyQuery: q test:^(uint64_t n, CBLQueryRow *row) {
        AssertEqualObjects(row.documentID, expectedDocs[n-1]);
        NSString* zip = [row stringAtIndex: 0];
        NSArray *email = [row valueAtIndex: 1];
        AssertEqualObjects(zip, expectedZips[n-1]);
        AssertEqualObjects(email, expectedEmails[n-1]);
    }];
    AssertEqual((int)numRows, 3);
}


- (void) test05_FTS {
    [self loadJSONResource: @"sentences"];
    NSError* error;
    Assert([_db createIndexOn: @[@"sentence"] type: kCBLFullTextIndex options: NULL error: &error]);
    CBLQuery *q = [self.db createQueryWhere: @"sentence matches 'Dummie woman'"];
    q.orderBy = @[@"-rank(sentence)"];
    q.returning = nil;
    uint64_t numRows = [self verifyQuery: q test:^(uint64_t n, CBLQueryRow *row) {
        CBLFullTextQueryRow* ftsRow = (id)row;
        NSString* text = ftsRow.fullTextMatched;
        NSLog(@"    full text = \"%@\"", text);
        NSLog(@"    matchCount = %u", (unsigned)ftsRow.matchCount);
        Assert([text containsString: @"Dummie"]);
        Assert([text containsString: @"woman"]);
        AssertEqual(ftsRow.matchCount, 2ul);
    }];
    AssertEqual((int)numRows, 2);
}


- (void) test07_deleteQueriedDoc {
    [self loadJSONResource: @"names_100"];
    
    NSError* error;
    NSArray* indexSpec = @[ [NSExpression expressionForKeyPath: @"name.first"] ];
    Assert([self.db createIndexOn: indexSpec type: kCBLValueIndex options: NULL error: &error]);
    
    CBLQuery *q = [self.db createQueryWhere: @"name.first == $FIRSTNAME"];
    q.parameters = @{@"FIRSTNAME": @"Claude"};
    
    NSArray* rows = [[q run: &error] allObjects];
    Assert(rows, @"Couldn't run query: %@", error);
    AssertEqual(rows.count, 1llu);
    
    CBLDocument* doc = ((CBLQueryRow*)rows[0]).document;
    AssertNotNil(doc);
    Assert([doc deleteDocument: &error], @"Couldn't delete a document: %@", error);
}


- (void) test08_Aggregate {
    [self loadJSONResource: @"names_100"];
    CBLQuery *q = [self.db createQueryWhere: @"gender == 'female'"];
    q.returning = @[@"min(contact.address.zip)", @"max(contact.address.zip)"];

    NSData* json = [q encodeAsJSON: NULL];
    NSString* jsonStr = [[NSString alloc] initWithData: json encoding: NSUTF8StringEncoding];
    NSLog(@"%@", jsonStr);

    uint64_t numRows = [self verifyQuery: q test:^(uint64_t n, CBLQueryRow *row) {
        //AssertEqualObjects(row.documentID, nil);
        NSString* minZip = [row stringAtIndex: 0];
        NSString* maxZip = [row stringAtIndex: 1];
        AssertEqualObjects(minZip, @"01910");
        AssertEqualObjects(maxZip, @"98434");
    }];
    AssertEqual((int)numRows, 1);
}


- (void) test09_GroupBy {
    NSArray* expectedStates = @[@"AL",    @"CA",    @"CO",    @"FL",    @"IA"];
    NSArray* expectedCounts = @[@1,       @6,       @1,       @1,       @3];
    NSArray* expectedMaxZips= @[@"35243", @"94153", @"81223", @"33612", @"50801"];

    [self loadJSONResource: @"names_100"];
    CBLQuery *q = [self.db createQueryWhere: @"gender == 'female'"];
    q.groupBy = @[@"contact.address.state"];
    q.orderBy = @[@"contact.address.state"];
    q.returning = @[@"contact.address.state", @"count(1)", @"max(contact.address.zip)"];

    NSData* json = [q encodeAsJSON: NULL];
    NSString* jsonStr = [[NSString alloc] initWithData: json encoding: NSUTF8StringEncoding];
    NSLog(@"%@", jsonStr);

    uint64_t numRows = [self verifyQuery: q test:^(uint64_t n, CBLQueryRow *row) {
        //AssertEqualObjects(row.documentID, nil);
        NSString* state = [row stringAtIndex: 0];
        NSInteger count = [row integerAtIndex: 1];
        NSString* maxZip = [row stringAtIndex: 2];
        //NSLog(@"State = %@, count = %d, maxZip = %@", state, (int)count,maxZip);
        if (n-1 < expectedStates.count) {
            AssertEqualObjects(state,  expectedStates[n-1]);
            AssertEqual       (count,  [expectedCounts[n-1] integerValue]);
            AssertEqualObjects(maxZip, expectedMaxZips[n-1]);
        }
    }];
    AssertEqual((int)numRows, 31);
}


@end
