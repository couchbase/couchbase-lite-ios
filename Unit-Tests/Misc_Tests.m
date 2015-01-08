//
//  Misc_Tests.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/7/15.
//
//

#import "CBLTestCase.h"
#import "CBLMisc.h"
#import "CBLSequenceMap.h"


@interface Misc_Tests : CBLTestCase
@end


@implementation Misc_Tests


- (void) test_CBLQuoteString {
    AssertEqual(CBLQuoteString(@""), @"\"\"");
    AssertEqual(CBLQuoteString(@"foo"), @"\"foo\"");
    AssertEqual(CBLQuoteString(@"f\"o\"o"), @"\"f\\\"o\\\"o\"");
    AssertEqual(CBLQuoteString(@"\\foo"), @"\"\\\\foo\"");
    AssertEqual(CBLQuoteString(@"\""), @"\"\\\"\"");
    AssertEqual(CBLQuoteString(@""), @"\"\"");

    AssertEqual(CBLUnquoteString(@""), @"");
    AssertEqual(CBLUnquoteString(@"\""), nil);
    AssertEqual(CBLUnquoteString(@"\"\""), @"");
    AssertEqual(CBLUnquoteString(@"\"foo"), nil);
    AssertEqual(CBLUnquoteString(@"foo\""), @"foo\"");
    AssertEqual(CBLUnquoteString(@"foo"), @"foo");
    AssertEqual(CBLUnquoteString(@"\"foo\""), @"foo");
    AssertEqual(CBLUnquoteString(@"\"f\\\"o\\\"o\""), @"f\"o\"o");
    AssertEqual(CBLUnquoteString(@"\"\\foo\""), @"foo");
    AssertEqual(CBLUnquoteString(@"\"\\\\foo\""), @"\\foo");
    AssertEqual(CBLUnquoteString(@"\"foo\\\""), nil);
}


- (void) test_CBLEscapeURLParam {
    AssertEqual(CBLEscapeURLParam(@"foobar"), @"foobar");
    AssertEqual(CBLEscapeURLParam(@"<script>alert('ARE YOU MY DADDY?')</script>"),
                 @"%3Cscript%3Ealert%28%27ARE%20YOU%20MY%20DADDY%3F%27%29%3C%2Fscript%3E");
    AssertEqual(CBLEscapeURLParam(@"foo/bar"), @"foo%2Fbar");
    AssertEqual(CBLEscapeURLParam(@"foo&bar"), @"foo%26bar");
    AssertEqual(CBLEscapeURLParam(@":/?#[]@!$&'()*+,;="),
                 @"%3A%2F%3F%23%5B%5D%40%21%24%26%27%28%29%2A%2B%2C%3B%3D");
}


- (void) test_CBLGetHostName {
    NSString* host = CBLGetHostName();
    Log(@"CBLGetHostName returned: <%@>", host);
    Assert(host, @"Can't get hostname");
    Assert([host rangeOfString: @"^[-a-zA-Z0-9]+\\.local\\.?$"
                       options: NSRegularExpressionSearch].length > 0,
           @"Invalid hostname: \"%@\"", host);
}


- (void) test_CBLGeometry {
    // Convert a rect to GeoJSON and back:
    CBLGeoRect rect = {{-115,-10}, {-90, 12}};
    NSDictionary* json = @{@"type": @"Polygon",
                           @"coordinates": @[ @[
                                   @[@-115,@-10], @[@-115, @12], @[@-90, @12],
                                   @[@-90, @-10], @[@-115, @-10]
                                   ]]};
    AssertEqual(CBLGeoRectToJSON(rect), json);

    CBLGeoRect bbox;
    Assert(CBLGeoJSONBoundingBox(json, &bbox));
    Assert(CBLGeoRectEqual(bbox, rect));

    Assert(CBLGeoCoordsStringToRect(@"-115,-10,-90,12.0",&bbox));
    Assert(CBLGeoRectEqual(bbox, rect));
}


static BOOL parseRevID(NSString* revID, int *gen, NSString** suffix) {
    return [CBL_Revision parseRevID: revID intoGeneration: gen andSuffix: suffix];
}

static int collateRevs(const char* rev1, const char* rev2) {
    return CBLCollateRevIDs(NULL, (int)strlen(rev1), rev1, (int)strlen(rev2), rev2);
}

- (void) test_ParseRevID {
    RequireTestCase(CBLDatabase);
    int num;
    NSString* suffix;
    Assert(parseRevID(@"1-utiopturoewpt", &num, &suffix));
    AssertEq(num, 1);
    AssertEqual(suffix, @"utiopturoewpt");
    
    Assert(parseRevID(@"321-fdjfdsj-e", &num, &suffix));
    AssertEq(num, 321);
    AssertEqual(suffix, @"fdjfdsj-e");
    
    Assert(!parseRevID(@"0-fdjfdsj-e", &num, &suffix));
    Assert(!parseRevID(@"-4-fdjfdsj-e", &num, &suffix));
    Assert(!parseRevID(@"5_fdjfdsj-e", &num, &suffix));
    Assert(!parseRevID(@" 5-fdjfdsj-e", &num, &suffix));
    Assert(!parseRevID(@"7 -foo", &num, &suffix));
    Assert(!parseRevID(@"7-", &num, &suffix));
    Assert(!parseRevID(@"7", &num, &suffix));
    Assert(!parseRevID(@"eiuwtiu", &num, &suffix));
    Assert(!parseRevID(@"", &num, &suffix));
}

- (void) test_CBLCollateRevIDs {
    // Single-digit:
    AssertEq(collateRevs("1-foo", "1-foo"), 0);
    AssertEq(collateRevs("2-bar", "1-foo"), 1);
    AssertEq(collateRevs("1-foo", "2-bar"), -1);
    // Multi-digit:
    AssertEq(collateRevs("123-bar", "456-foo"), -1);
    AssertEq(collateRevs("456-foo", "123-bar"), 1);
    AssertEq(collateRevs("456-foo", "456-foo"), 0);
    AssertEq(collateRevs("456-foo", "456-foofoo"), -1);
    // Different numbers of digits:
    AssertEq(collateRevs("89-foo", "123-bar"), -1);
    AssertEq(collateRevs("123-bar", "89-foo"), 1);
    // Edge cases:
    AssertEq(collateRevs("123-", "89-"), 1);
    AssertEq(collateRevs("123-a", "123-a"), 0);
    // Invalid rev IDs:
    AssertEq(collateRevs("-a", "-b"), -1);
    AssertEq(collateRevs("-", "-"), 0);
    AssertEq(collateRevs("", ""), 0);
    AssertEq(collateRevs("", "-b"), -1);
    AssertEq(collateRevs("bogus", "yo"), -1);
    AssertEq(collateRevs("bogus-x", "yo-y"), -1);
}


- (void) test_CBLSequenceMap {
    CBLSequenceMap* map = [[CBLSequenceMap alloc] init];
    AssertEq(map.checkpointedSequence, 0);
    AssertEqual(map.checkpointedValue, nil);
    Assert(map.isEmpty);
    
    AssertEq([map addValue: @"one"], 1);
    AssertEq(map.checkpointedSequence, 0);
    AssertEqual(map.checkpointedValue, nil);
    Assert(!map.isEmpty);
    
    AssertEq([map addValue: @"two"], 2);
    AssertEq(map.checkpointedSequence, 0);
    AssertEqual(map.checkpointedValue, nil);
    
    AssertEq([map addValue: @"three"], 3);
    AssertEq(map.checkpointedSequence, 0);
    AssertEqual(map.checkpointedValue, nil);
    
    [map removeSequence: 2];
    AssertEq(map.checkpointedSequence, 0);
    AssertEqual(map.checkpointedValue, nil);
    
    [map removeSequence: 1];
    AssertEq(map.checkpointedSequence, 2);
    AssertEqual(map.checkpointedValue, @"two");
    
    AssertEq([map addValue: @"four"], 4);
    AssertEq(map.checkpointedSequence, 2);
    AssertEqual(map.checkpointedValue, @"two");
    
    [map removeSequence: 3];
    AssertEq(map.checkpointedSequence, 3);
    AssertEqual(map.checkpointedValue, @"three");
    
    [map removeSequence: 4];
    AssertEq(map.checkpointedSequence, 4);
    AssertEqual(map.checkpointedValue, @"four");
    Assert(map.isEmpty);
}


@end
