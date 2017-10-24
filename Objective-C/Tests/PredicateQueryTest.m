//
//  PredicateQueryTest.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/13/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLTestCase.h"
#import "CBLDatabase+Internal.h"
#import "CBLPredicateQuery+Internal.h"
#import "CBLJSON.h"


@interface PredicateQueryTest : CBLTestCase

@end


@implementation PredicateQueryTest


- (CBLMutableDocument*) docForRow: (CBLQueryRow*)row {
    NSString* docID = [row stringAtIndex: 0];
    C4SequenceNumber sequence = [row integerAtIndex: 1];
    CBLMutableDocument* doc = [_db documentWithID: docID];
    AssertEqual(doc.sequence, sequence);
    return doc;
}


- (uint64_t) verifyQuery: (CBLPredicateQuery*)q test: (void (^)(uint64_t n, CBLQueryRow *row))block {
    NSError* error;
    NSEnumerator* e = [q run: &error];
    Assert(e, @"Query failed: %@", error);
    uint64_t n = 0;
    for (CBLQueryRow *row in e) {
        //Log(@"Row: docID='%@', sequence=%llu", row.documentID, row.sequence);
        block(++n, row);
    }
    return n;
}


- (void) testPredicates {
    // The query with the 'matches' operator requires there to be a FTS index on 'blurb':
    NSError* error;
    CBLQueryExpression* blurb = [CBLQueryExpression property: @"blurb"];
    CBLIndex* index = [CBLIndex ftsIndexOn: [CBLFTSIndexItem expression: blurb] options: nil];
    Assert([_db createIndex: index withName: @"blurb" error: &error]);
    
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
        {"name ==[c] 'Bobo'",       "{WHERE: ['COLLATE', {UNICODE:true, CASE:false}, ['=', ['.name'], 'Bobo']]}"},
        {"name ==[d] 'Bobo'",       "{WHERE: ['COLLATE', {UNICODE:true, DIAC:false}, ['=', ['.name'], 'Bobo']]}"},
        {"name ==[cd] 'Bobo'",      "{WHERE: ['COLLATE', {UNICODE:true, CASE:false, DIAC:false}, ['=', ['.name'], 'Bobo']]}"},
        {"sum(prices) > 100",       "{WHERE: ['>', ['ARRAY_SUM()', ['.prices']], 100]}"},
        {"age + 10 == 62",          "{WHERE: ['=', ['+', ['.age'], 10], 62]}"},
        {"foo + 'bar' == 'foobar'", "{WHERE: ['=', ['||', ['.foo'], 'bar'], 'foobar']}"},
        {"FUNCTION(email, 'REGEXP_LIKE', '.+@.+') == true",
                                    "{WHERE: ['=', ['REGEXP_LIKE()', ['.email'], '.+@.+'], true]}"},
        {"TERNARY(2==3, 1, 2) == 1", "{WHERE: ['=', ['CASE', null, ['=', 2, 3], 1, 2], 1]}"},
        {"x == nil",                "{WHERE: ['IS', ['.x'], ['MISSING']]}"},
        {"x != nil",                "{WHERE: ['IS NOT', ['.x'], ['MISSING']]}"},
    };
    for (unsigned i = 0; i < sizeof(kTests)/sizeof(kTests[0]); ++i) {
        NSString* pred = @(kTests[i].pred);
        //[CBLQuery dumpPredicate: [NSPredicate predicateWithFormat: pred argumentArray: nil]];
        NSString* expectedJson = [CBLPredicateQuery json5ToJSON: kTests[i].json5];
        CBLPredicateQuery* query = [self.db createQueryWhere: pred];
        query.orderBy = nil; // ignore ordering in this test
        query.disableOffsetAndLimit = true;
        NSData* actual = [query encodeAsJSON: &error];
        Assert(actual, @"Encode failed: %@", error);
        NSString* actualJSON = [[NSString alloc] initWithData: actual encoding: NSUTF8StringEncoding];
        AssertEqualObjects(actualJSON, expectedJson);

        Assert([query check: &error], @"Couldn't compile CBLQuery: %@", error);
    }
}


- (void) testNoWhereQuery {
    [self loadJSONResource: @"names_100"];
    NSError *error;
    // This is an all-docs query since it doesn't specify any criteria:
    CBLPredicateQuery* q = [self.db createQueryWhere: nil];
    Assert(q, @"Couldn't create query: %@", error);
    uint64_t numRows = [self verifyQuery: q test:^(uint64_t n, CBLQueryRow *row) {
        NSString* expectedID = [NSString stringWithFormat: @"doc-%03llu", n];
        AssertEqualObjects([row stringAtIndex: 0], expectedID);
        AssertEqual((uint64_t)[row integerAtIndex: 1], n);
    }];
    AssertEqual(numRows, 100llu);
}


- (void) testOffsetAndLimit {
    [self loadJSONResource: @"names_100"];
    NSError *error;
    CBLPredicateQuery* q = [self.db createQueryWhere: @"gender = 'male'"];
    Assert(q, @"Couldn't create query: %@", error);
    q.offset = 5;
    q.limit = 10;
    __block NSMutableArray* docIDs = [NSMutableArray new];
    [self verifyQuery: q test:^(uint64_t n, CBLQueryRow *row) {
        [docIDs addObject: [row stringAtIndex: 0]];
    }];
    AssertEqualObjects(docIDs, (@[@"doc-011",
                                  @"doc-014",
                                  @"doc-015",
                                  @"doc-017",
                                  @"doc-020",
                                  @"doc-021",
                                  @"doc-024",
                                  @"doc-025",
                                  @"doc-026",
                                  @"doc-027"]));
}


- (void) testSortDescriptors {
    // Strings:
    [self testSortDescriptor: @"name" expectingJSON: "['.name']"];
    [self testSortDescriptor: @"name.first" expectingJSON: "['.name.first']"];
    [self testSortDescriptor: @"name[]" expectingJSON: "['COLLATE', {UNICODE:true}, ['.name']]"];
    [self testSortDescriptor: @"name[c]" expectingJSON: "['COLLATE', {UNICODE:true, CASE:false}, ['.name']]"];
    [self testSortDescriptor: @"name[d]" expectingJSON: "['COLLATE', {UNICODE:true, DIAC:false}, ['.name']]"];
    [self testSortDescriptor: @"name[cd]" expectingJSON: "['COLLATE', {UNICODE:true, CASE:false, DIAC:false}, ['.name']]"];

    [self testSortDescriptor: @"-name" expectingJSON: "['DESC', ['.name']]"];
    [self testSortDescriptor: @"-name[c]" expectingJSON: "['DESC', ['COLLATE', {UNICODE:true, CASE:false}, ['.name']]]"];

    // NSSortDescriptors:
    [self testSortDescriptor: [NSSortDescriptor sortDescriptorWithKey: @"name" ascending: YES]
               expectingJSON: "['.name']"];
    [self testSortDescriptor: [NSSortDescriptor sortDescriptorWithKey: @"name" ascending: NO]
               expectingJSON: "['DESC', ['.name']]"];
    [self testSortDescriptor: [NSSortDescriptor sortDescriptorWithKey: @"name" ascending: YES
                                                             selector: @selector(compare:)]
               expectingJSON: "['.name']"];
    [self testSortDescriptor: [NSSortDescriptor sortDescriptorWithKey: @"name" ascending: YES
                                                             selector: @selector(localizedCompare:)]
               expectingJSON: "['COLLATE', {UNICODE:true}, ['.name']]"];
    [self testSortDescriptor: [NSSortDescriptor sortDescriptorWithKey: @"name" ascending: YES
                                                             selector: @selector(localizedCaseInsensitiveCompare:)]
               expectingJSON: "['COLLATE', {UNICODE:true, CASE:false}, ['.name']]"];
    [self testSortDescriptor: [NSSortDescriptor sortDescriptorWithKey: @"name" ascending: YES
                                                             selector: @selector(caseInsensitiveCompare:)]
               expectingJSON: "['COLLATE', {CASE:false}, ['.name']]"];
    [self testSortDescriptor: [NSSortDescriptor sortDescriptorWithKey: @"name" ascending: NO
                                                             selector: @selector(localizedCompare:)]
               expectingJSON: "['DESC', ['COLLATE', {UNICODE:true}, ['.name']]]"];
}

- (void) testSortDescriptor: (id)sd expectingJSON: (const char*)json5 {
    NSError* error;
    NSArray* sorts = [CBLPredicateQuery encodeSortDescriptors: @[sd] error: &error];
    Assert(sorts, @"encodeSortDescriptors failed: %@", error);
    NSString* actual = [CBLJSON stringWithJSONObject: sorts[0] options: 0 error: &error];
    AssertEqualObjects(actual, [CBLPredicateQuery json5ToJSON: json5]);
}


- (void) testAllDocsQuery {
    [self loadJSONResource: @"names_100"];
    uint64_t n = 0;
    for (CBLMutableDocument* doc in self.db.allDocuments) {
        ++n;
        NSString* expectedID = [NSString stringWithFormat: @"doc-%03llu", n];
        AssertEqualObjects(doc.id, expectedID);
        AssertEqual(doc.sequence, n);
    }
    AssertEqual(n, 100llu);
}


- (void) testPropertyQuery               {[self propertyQueryWithReopen: NO];}
- (void) testPropertyQueryAfterReopen    {[self propertyQueryWithReopen: YES];}

- (void) propertyQueryWithReopen: (BOOL)reopen {
    [self loadJSONResource: @"names_100"];
    if (reopen)
        [self reopenDB];

    // Try a query involving a property. The first pass will be unindexed, the 2nd indexed.
    NSError *error;
    CBLQueryExpression* firstName = [CBLQueryExpression property: @"name.first"];
    CBLIndex* index = [CBLIndex valueIndexOn: @[[CBLValueIndexItem expression: firstName]]];
    
    for (int pass = 0; pass < 2; ++pass) {
        Log(@"---- Pass %d", pass);
        CBLPredicateQuery *q = [self.db createQueryWhere: @"name.first == $FIRSTNAME"];
        Assert(q, @"Couldn't create query: %@", error);
        NSString* explain = [q explain: &error];
        Assert(explain, @"-explain failed: %@", error);
        //fprintf(stderr, "%s\n", explain.UTF8String);
        q.parameters = @{@"FIRSTNAME": @"Claude"};
        uint64_t numRows = [self verifyQuery: q test:^(uint64_t n, CBLQueryRow *row) {
            NSString* docID = [row stringAtIndex: 0];
            AssertEqualObjects(docID, @"doc-009");
            AssertEqual((uint64_t)[row integerAtIndex: 1], 9llu);
            CBLMutableDocument* doc = [self docForRow: row];
            AssertEqualObjects(doc.id, @"doc-009");
            AssertEqual(doc.sequence, 9llu);
            AssertEqualObjects([[doc objectForKey: @"name"] objectForKey: @"first"], @"Claude");
        }];
        AssertEqual(numRows, 1llu);
        if (pass == 0)
            Assert([_db createIndex: index withName: @"name.first" error: &error]);
    }
    
    Assert([self.db deleteIndexForName: @"name.first" error: &error]);
}


- (void) testProjection {
    NSArray* expectedZips = @[@"55587", @"56307", @"56308"];
    NSArray* expectedEmails = @[ @[@"monte.mihlfeld@nosql-matters.org"],
                                 @[@"jennefer.menning@nosql-matters.org", @"jennefer@nosql-matters.org"],
                                 @[@"stephen.jakovac@nosql-matters.org"] ];

    [self loadJSONResource: @"names_100"];
    CBLPredicateQuery *q = [self.db createQueryWhere: @"contact.address.state == $STATE"];
    q.orderBy = @[@"contact.address.zip"];
    q.returning = @[@"contact.address.zip", @"contact.email"];
    q.parameters = @{@"STATE": @"MN"};
    uint64_t numRows = [self verifyQuery: q test:^(uint64_t n, CBLQueryRow *row) {
        NSString* zip = [row stringAtIndex: 0];
        NSArray *email = [row valueAtIndex: 1];
        AssertEqualObjects(zip, expectedZips[(NSUInteger)(n-1)]);
        AssertEqualObjects(email, expectedEmails[(NSUInteger)(n-1)]);
    }];
    AssertEqual((int)numRows, 3);
}


- (void) testFTS {
    [self loadJSONResource: @"sentences"];
    NSError* error;
    CBLQueryExpression* sentence = [CBLQueryExpression property: @"sentence"];
    CBLIndex* index = [CBLIndex ftsIndexOn: [CBLFTSIndexItem expression: sentence] options: nil];
    Assert([_db createIndex: index withName: @"sentence" error: &error]);
    
    CBLPredicateQuery *q = [self.db createQueryWhere: @"sentence matches 'Dummie woman'"];
    q.orderBy = @[@"-rank(sentence)"];
    q.returning = nil;
    uint64_t numRows = [self verifyQuery: q test:^(uint64_t n, CBLQueryRow *row) {
        CBLFullTextQueryRow* ftsRow = (id)row;
        NSString* text = ftsRow.fullTextMatched;
//        Log(@"    full text = \"%@\"", text);
//        Log(@"    matchCount = %u", (unsigned)ftsRow.matchCount);
        Assert([text containsString: @"Dummie"]);
        Assert([text containsString: @"woman"]);
        AssertEqual(ftsRow.matchCount, 2ul);
    }];
    AssertEqual((int)numRows, 2);
}


- (void) testAggregate {
    [self loadJSONResource: @"names_100"];
    CBLPredicateQuery *q = [self.db createQueryWhere: @"gender == 'female'"];
    q.returning = @[@"min(contact.address.zip)", @"max(contact.address.zip)"];

    NSData* json = [q encodeAsJSON: NULL];
    NSString* jsonStr = [[NSString alloc] initWithData: json encoding: NSUTF8StringEncoding];
    Log(@"%@", jsonStr);

    uint64_t numRows = [self verifyQuery: q test:^(uint64_t n, CBLQueryRow *row) {
        NSString* minZip = [row stringAtIndex: 0];
        NSString* maxZip = [row stringAtIndex: 1];
        AssertEqualObjects(minZip, @"01910");
        AssertEqualObjects(maxZip, @"98434");
    }];
    AssertEqual((int)numRows, 1);
}


- (void) testGroupBy {
    NSArray* expectedStates = @[@"AL",    @"CA",    @"CO",    @"FL",    @"IA"];
    NSArray* expectedCounts = @[@1,       @6,       @1,       @1,       @3];
    NSArray* expectedMaxZips= @[@"35243", @"94153", @"81223", @"33612", @"50801"];

    [self loadJSONResource: @"names_100"];
    CBLPredicateQuery *q = [self.db createQueryWhere: @"gender ==[c] 'FEMALE'"];
    q.groupBy = @[@"contact.address.state"];
    q.orderBy = @[@"contact.address.state"];
    q.returning = @[@"contact.address.state", @"count(1)", @"max(contact.address.zip)"];

    NSData* json = [q encodeAsJSON: NULL];
    NSString* jsonStr = [[NSString alloc] initWithData: json encoding: NSUTF8StringEncoding];
    Log(@"%@", jsonStr);
    Log(@"%@", [q explain: NULL]);

    uint64_t numRows = [self verifyQuery: q test:^(uint64_t n, CBLQueryRow *row) {
        AssertEqual(row.valueCount, 3u);
        NSString* state = [row stringAtIndex: 0];
        NSInteger count = [row integerAtIndex: 1];
        NSString* maxZip = [row stringAtIndex: 2];
        //Log(@"State = %@, count = %d, maxZip = %@", state, (int)count,maxZip);
        if (n-1 < expectedStates.count) {
            AssertEqualObjects(state,  expectedStates[(NSUInteger)(n-1)]);
            AssertEqual       (count,  [expectedCounts[(NSUInteger)(n-1)] integerValue]);
            AssertEqualObjects(maxZip, expectedMaxZips[(NSUInteger)(n-1)]);
        }
    }];
    AssertEqual((int)numRows, 31);
}


- (void) failingTest10_Like {
    // https://github.com/couchbase/couchbase-lite-ios/issues/1667
    [self loadJSONResource: @"names_100"];
    
    CBLPredicateQuery *q = [self.db createQueryWhere: @"name.first LIKE 'Mar*'"];
    q.orderBy = @[@"name.first"];
    
    NSArray* expected = @[@"Marcy", @"Marlen", @"Maryjo", @"Margaretta", @"Margrett"];
    uint64_t numRows = [self verifyQuery: q test:^(uint64_t n, CBLQueryRow *row) {
        CBLMutableDocument* doc = [self docForRow: row];
        AssertEqualObjects(doc[@"name"][@"first"], expected[(NSUInteger)(n-1)]);
    }];
    AssertEqual((int)numRows, (int)expected.count);
}


- (void) failingTest11_Regexp {
    // https://github.com/couchbase/couchbase-lite-ios/issues/1668
    [self loadJSONResource: @"names_100"];
    
    CBLPredicateQuery *q = [self.db createQueryWhere:
                            @"name.first == FUNCTION(name.first, 'REGEXP_LIKE' , '^Mar.*')"];
    q.orderBy = @[@"name.first"];
    
    NSArray* expected = @[@"Marcy", @"Marlen", @"Maryjo", @"Margaretta", @"Margrett"];
    uint64_t numRows = [self verifyQuery: q test:^(uint64_t n, CBLQueryRow *row) {
        CBLMutableDocument* doc = [self docForRow: row];
        AssertEqualObjects(doc[@"name"][@"first"], expected[(NSUInteger)(n-1)]);
    }];
    AssertEqual((int)numRows, (int)expected.count);
}


- (void) failingTest12_SelectDistinct {
    // https://github.com/couchbase/couchbase-lite-ios/issues/1669
    for (int i = 0; i < 10; i++) {
        NSError* error;
        CBLMutableDocument* doc = [[CBLMutableDocument alloc] init];
        [doc setObject: @(1) forKey: @"number"];
        Assert([_db saveDocument: doc error:&error], @"Error when creating a document: %@", error);
    }
    
    CBLPredicateQuery *q = [self.db createQueryWhere: nil];
    q.returning = @[@"number"];
    q.distinct = YES;
    Assert(q);
    uint64_t numRows = [self verifyQuery: q test: ^(uint64_t n, CBLQueryRow *row) {
        CBLMutableDocument* doc = [self docForRow: row];
        AssertEqualObjects(doc.toDictionary, @{@"number": @(1)});
    }];
    AssertEqual(numRows, 1u);
}


- (void) failingTest13_Null {
    // https://github.com/couchbase/couchbase-lite-ios/issues/1670
    NSError* error;
    CBLMutableDocument* doc1 = [self.db documentWithID: @"doc1"];
    [doc1 setObject: @"Scott" forKey: @"name"];
    [doc1 setObject: [NSNull null] forKey: @"address"];
    Assert([_db saveDocument: doc1 error: &error], @"Error when saving a document: %@", error);
    
    CBLMutableDocument* doc2 = [self.db documentWithID: @"doc2"];
    [doc2 setObject: @"Tiger" forKey: @"name"];
    [doc2 setObject: @"123 1st ave." forKey: @"address"];
    [doc2 setObject: @(20) forKey: @"age"];
    Assert([_db saveDocument: doc2 error: &error], @"Error when saving a document: %@", error);
    
    NSArray* tests = @[
                       @[@"name != null",    @[doc1, doc2]],
                       @[@"name == null",    @[]],
                       @[@"address != null", @[doc2]],
                       @[@"address == null", @[doc1]],
                       @[@"age != null",     @[doc2]],
                       @[@"age == null",     @[doc1]],
                       @[@"work != null",    @[]],
                       @[@"work == null",    @[doc1, doc2]],
                       ];
    
    for (NSArray* test in tests) {
        NSString* predicate = test[0];
        NSArray* expectedDocs = test[1];
        Log(@"Predicate: %@", predicate);
        CBLPredicateQuery *q = [self.db createQueryWhere: predicate];
        uint64_t numRows = [self verifyQuery: q test:^(uint64_t n, CBLQueryRow *row) {
            
        }];
        AssertEqual((int)numRows, (int)expectedDocs.count);
    }
}


- (void) testWhereIn {
    [self loadJSONResource: @"names_100"];
    
    CBLPredicateQuery *q = [self.db createQueryWhere:
        @"name.first IN {'Marcy', 'Marlen', 'Maryjo', 'Margaretta', 'Margrett'}"];
    q.orderBy = @[@"name.first"];
    
    NSArray* expected = @[@"Marcy", @"Margaretta", @"Margrett", @"Marlen", @"Maryjo"];
    uint64_t numRows = [self verifyQuery: q test:^(uint64_t n, CBLQueryRow *row) {
        CBLMutableDocument* doc = [self docForRow: row];
        NSString* first = [[doc objectForKey: @"name"] objectForKey: @"first"];
        AssertEqualObjects(first, expected[(NSUInteger)(n-1)]);
    }];
    AssertEqual((int)numRows, (int)expected.count);
}

@end
