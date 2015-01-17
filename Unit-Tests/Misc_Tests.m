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
#import "CBLFacebookAuthorizer.h"
#import "CBLPersonaAuthorizer.h"


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


- (void) test_FacebookAuthorizer {
    NSString* token = @"pyrzqxgl";
    NSURL* site = [NSURL URLWithString: @"https://example.com/database"];
    NSString* email = @"jimbo@example.com";

    CBLFacebookAuthorizer* auth = [[CBLFacebookAuthorizer alloc] initWithEmailAddress: email];

    // Register and retrieve the sample token:
    Assert([CBLFacebookAuthorizer registerToken: token
                                 forEmailAddress: email forSite: site]);
    NSString* gotToken = [auth tokenForSite: site];
    AssertEqual(gotToken, token);

    // Try a variant form of the URL:
    gotToken = [auth tokenForSite: [NSURL URLWithString: @"HttpS://example.com:443/some/other/path"]];
    AssertEqual(gotToken, token);

    AssertEqual([auth loginParametersForSite: site], (@{@"access_token": token}));
}


- (void) test_PersonaAuthorizer {
    NSString* email, *origin;
    NSDate* exp;
    Assert(!CBLParsePersonaAssertion(@"", &email, &origin, &exp));

    // This is an assertion generated by persona.org on 1/13/2013.
    NSString* sampleAssertion = @"eyJhbGciOiJSUzI1NiJ9.eyJwdWJsaWMta2V5Ijp7ImFsZ29yaXRobSI6IkRTIiwieSI6ImNhNWJiYTYzZmI4MDQ2OGE0MjFjZjgxYTIzN2VlMDcwYTJlOTM4NTY0ODhiYTYzNTM0ZTU4NzJjZjllMGUwMDk0ZWQ2NDBlOGNhYmEwMjNkYjc5ODU3YjkxMzBlZGNmZGZiNmJiNTUwMWNjNTk3MTI1Y2NiMWQ1ZWQzOTVjZTMyNThlYjEwN2FjZTM1ODRiOWIwN2I4MWU5MDQ4NzhhYzBhMjFlOWZkYmRjYzNhNzNjOTg3MDAwYjk4YWUwMmZmMDQ4ODFiZDNiOTBmNzllYzVlNDU1YzliZjM3NzFkYjEzMTcxYjNkMTA2ZjM1ZDQyZmZmZjQ2ZWZiZDcwNjgyNWQiLCJwIjoiZmY2MDA0ODNkYjZhYmZjNWI0NWVhYjc4NTk0YjM1MzNkNTUwZDlmMWJmMmE5OTJhN2E4ZGFhNmRjMzRmODA0NWFkNGU2ZTBjNDI5ZDMzNGVlZWFhZWZkN2UyM2Q0ODEwYmUwMGU0Y2MxNDkyY2JhMzI1YmE4MWZmMmQ1YTViMzA1YThkMTdlYjNiZjRhMDZhMzQ5ZDM5MmUwMGQzMjk3NDRhNTE3OTM4MDM0NGU4MmExOGM0NzkzMzQzOGY4OTFlMjJhZWVmODEyZDY5YzhmNzVlMzI2Y2I3MGVhMDAwYzNmNzc2ZGZkYmQ2MDQ2MzhjMmVmNzE3ZmMyNmQwMmUxNyIsInEiOiJlMjFlMDRmOTExZDFlZDc5OTEwMDhlY2FhYjNiZjc3NTk4NDMwOWMzIiwiZyI6ImM1MmE0YTBmZjNiN2U2MWZkZjE4NjdjZTg0MTM4MzY5YTYxNTRmNGFmYTkyOTY2ZTNjODI3ZTI1Y2ZhNmNmNTA4YjkwZTVkZTQxOWUxMzM3ZTA3YTJlOWUyYTNjZDVkZWE3MDRkMTc1ZjhlYmY2YWYzOTdkNjllMTEwYjk2YWZiMTdjN2EwMzI1OTMyOWU0ODI5YjBkMDNiYmM3ODk2YjE1YjRhZGU1M2UxMzA4NThjYzM0ZDk2MjY5YWE4OTA0MWY0MDkxMzZjNzI0MmEzODg5NWM5ZDViY2NhZDRmMzg5YWYxZDdhNGJkMTM5OGJkMDcyZGZmYTg5NjIzMzM5N2EifSwicHJpbmNpcGFsIjp7ImVtYWlsIjoiamVuc0Btb29zZXlhcmQuY29tIn0sImlhdCI6MTM1ODI5NjIzNzU3NywiZXhwIjoxMzU4MzgyNjM3NTc3LCJpc3MiOiJsb2dpbi5wZXJzb25hLm9yZyJ9.RnDK118nqL2wzpLCVRzw1MI4IThgeWpul9jPl6ypyyxRMMTurlJbjFfs-BXoPaOem878G8-4D2eGWS6wd307k7xlPysevYPogfFWxK_eDHwkTq3Ts91qEDqrdV_JtgULC8c1LvX65E0TwW_GL_TM94g3CvqoQnGVxxoaMVye4ggvR7eOZjimWMzUuu4Lo9Z-VBHBj7XM0UMBie57CpGwH4_Wkv0V_LHZRRHKdnl9ISp_aGwfBObTcHG9v0P3BW9vRrCjihIn0SqOJQ9obl52rMf84GD4Lcy9NIktzfyka70xR9Sh7ALotW7rWywsTzMTu3t8AzMz2MJgGjvQmx49QA~eyJhbGciOiJEUzEyOCJ9.eyJleHAiOjEzNTgyOTY0Mzg0OTUsImF1ZCI6Imh0dHA6Ly9sb2NhbGhvc3Q6NDk4NC8ifQ.4FV2TrUQffDya0MOxOQlzJQbDNvCPF2sfTIJN7KOLvvlSFPknuIo5g";
    Assert(CBLParsePersonaAssertion(sampleAssertion, &email, &origin, &exp));
    AssertEqual(email, @"jens@mooseyard.com");
    AssertEqual(origin, @"http://localhost:4984/");
    AssertEq((SInt64)exp.timeIntervalSinceReferenceDate, 379989238);

    // Register and retrieve the sample assertion:
    NSURL* originURL = [NSURL URLWithString: origin];
    AssertEqual([CBLPersonaAuthorizer registerAssertion: sampleAssertion], email);
    NSString* gotAssertion = [CBLPersonaAuthorizer assertionForEmailAddress: email
                                                                       site: originURL];
    AssertEqual(gotAssertion, sampleAssertion);

    // Try a variant form of the URL:
    originURL = [NSURL URLWithString: @"Http://LocalHost:4984"];
    gotAssertion = [CBLPersonaAuthorizer assertionForEmailAddress: email
                                                             site: originURL];
    AssertEqual(gotAssertion, sampleAssertion);

    // -assertionForSite: should return nil because the assertion has expired by now:
    CBLPersonaAuthorizer* auth = [[CBLPersonaAuthorizer alloc] initWithEmailAddress: email];
    AssertEqual(auth.emailAddress, email);
    AssertEqual([auth assertionForSite: originURL], nil);
}


@end
