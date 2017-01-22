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


- (void) test08_Predicates {
    const struct {const char *pred; const char *json5;} kTests[] = {
        {"nickname == 'Bobo'",      "{WHERE: ['=', ['.nickname'],'Bobo']}"},
        {"name.first == $FIRSTNAME","{WHERE: ['=', ['.name.first'],['$FIRSTNAME']]}"},
        {"ALL children.age < 18",   "{WHERE: ['EVERY','X',['.children'],['<',['?X','age'], 18]]}"},
        {"ANY children == 'Bobo'",  "{WHERE: ['ANY', 'X', ['.children'], ['=', ['?X'], 'Bobo']]}"},
        {"'Bobo' in children",      "{WHERE: ['ANY', 'X', ['.children'], ['=', ['?X'], 'Bobo']]}"},
        {"name in $NAMES",          "{WHERE: ['IN', ['.name'], ['$NAMES']]}"},
        {"fruit matches 'bana(na)+'","{WHERE: ['REGEXP_LIKE()', ['.fruit'], 'bana(na)+']}"},
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
    };
    for (unsigned i = 0; i < sizeof(kTests)/sizeof(kTests[0]); ++i) {
        NSString* pred = @(kTests[i].pred);
        [CBLQuery dumpPredicate: [NSPredicate predicateWithFormat: pred argumentArray: nil]];
        NSString* expectedJson = [CBLQuery json5ToJSON: kTests[i].json5];
        NSError *error;
        NSData* actual = [CBLQuery encodeQuery: pred orderBy: nil error: &error];
        XCTAssert(actual, @"Encode failed: %@", error);
        NSString* actualJSON = [[NSString alloc] initWithData: actual encoding: NSUTF8StringEncoding];
        XCTAssertEqualObjects(actualJSON, expectedJson);

        CBLQuery* query = [self.db createQuery: pred error: &error];
        XCTAssert(query, @"Couldn't create CBLQuery: %@", error);
    }
}


- (void) test09_Query {
    NSString* path = [[NSBundle bundleForClass: [self class]] pathForResource: @"names_100" ofType: @"json"];
    XCTAssert(path, @"Missing test file names_100.json");
    NSString* contents = (NSString*)[NSString stringWithContentsOfFile: path encoding: NSUTF8StringEncoding error: NULL];
    XCTAssert(contents);
    __block uint64_t n = 0;
    NSError *error;
    BOOL ok = [self.db inBatch: &error do:^BOOL{
        [contents enumerateLinesUsingBlock: ^(NSString *line, BOOL *stop) {
            CBLDocument* doc = [self.db documentWithID: [NSString stringWithFormat: @"person-%03llu", ++n]];
            doc.properties = [NSJSONSerialization JSONObjectWithData: (NSData*)[line dataUsingEncoding: NSUTF8StringEncoding] options: 0 error: NULL];
            NSError* saveError;
            XCTAssert([doc save: &saveError]);
        }];
        return true;
    }];
    XCTAssert(ok);

    // All-docs query:
    {
        CBLQuery* q = [self.db createQuery: nil error: &error];
        XCTAssert(q, @"Couldn't create query: %@", error);
        NSEnumerator* e = [q run: &error];
        XCTAssert(e);
        n = 0;
        for (CBLQueryRow *row in e) {
            ++n;
            NSLog(@"Row: docID='%@', sequence=%llu", row.documentID, row.sequence);
            NSString* expectedID = [NSString stringWithFormat: @"person-%03llu", n];
            XCTAssertEqualObjects(row.documentID, expectedID);
            XCTAssertEqual(row.sequence, n);
            CBLDocument* doc = row.document;
            XCTAssertEqualObjects(doc.documentID, expectedID);
            XCTAssertEqual(doc.sequence, n);
        }
        XCTAssertEqual(n, 100llu);
    }

    // Try a query involving a property. The first pass will be unindexed, the 2nd indexed.
    NSArray* indexSpec = @[ [NSExpression expressionForKeyPath: @"name.first"] ];
    for (int pass = 0; pass < 2; ++pass) {
        CBLQuery *q = [self.db createQuery: @"name.first == $FIRSTNAME" error: &error];
        XCTAssert(q, @"Couldn't create query: %@", error);
        q.parameters = @{@"FIRSTNAME": @"Claude"};
        NSEnumerator* e = [q run: &error];
        XCTAssert(e);
        n = 0;
        for (CBLQueryRow *row in e) {
            @autoreleasepool {
            ++n;
            NSLog(@"Row: docID='%@', sequence=%llu", row.documentID, row.sequence);
            XCTAssertEqualObjects(row.documentID, @"person-009");
            XCTAssertEqual(row.sequence, 9llu);
            CBLDocument* doc = row.document;
            XCTAssertEqualObjects(doc.documentID, @"person-009");
            XCTAssertEqual(doc.sequence, 9llu);
            }
        }
        XCTAssertEqual(n, 1llu);

        if (pass == 0) {
            XCTAssert([self.db createIndexOn: indexSpec type: kCBLValueIndex options: NULL error: &error]);
        }
    }
    XCTAssert([self.db deleteIndexOn: indexSpec type: kCBLValueIndex error: &error]);
}


@end
