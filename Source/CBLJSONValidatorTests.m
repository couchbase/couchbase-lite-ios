//
//  CBLJSONValidator.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/17/13.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBLJSONValidator.h"
#import "CBLJSON.h"
#import "Test.h"


// This test uses the official JSON-Schema test suite, embedded as a Git submodule.
// https://github.com/json-schema/JSON-Schema-Test-Suite

#if DEBUG
#if !TARGET_OS_IPHONE  // Test suite files are on desktop filesystem, not device

static NSArray* kIgnoredTests;

static id loadJSONFile(NSString* dir, NSString* filename) {
    NSString* path = [dir stringByAppendingPathComponent: filename];
    NSData* data = [NSData dataWithContentsOfFile: path];
    CAssert(data, @"Couldn't read file %@", path);
    id json = [CBLJSON JSONObjectWithData: data options: 0 error: nil];
    CAssert(json, @"Couldn't parse JSON file %@", path);
    return json;
}

static void RunJSONSchemaTestFile(NSString* filename, NSArray* testFile) {
    static unsigned sTestNo = 0;
    NSError* error;
    for (NSDictionary* testSet in testFile) {
        NSString* setName = testSet[@"description"];
        CBLJSONValidator* validator = [[CBLJSONValidator alloc] initWithSchema: testSet[@"schema"]];
        CAssert([validator selfValidate: &error], @"Self-validation failed: %@", error);
        for (NSDictionary* test in testSet[@"tests"]) {
            NSString* description = [NSString stringWithFormat: @"%@ / %@ / %@",
                                     filename, setName, test[@"description"]];
            LogTo(JSONSchema, @"---- #%2u: %@", ++sTestNo, description);
            bool valid = [validator validateJSONObject: test[@"data"] error: &error];
            if (!valid)
                LogTo(JSONSchema, @"      error: %@", error);
            if (valid != [test[@"valid"] boolValue]) {
                if ([kIgnoredTests containsObject: description])
                    Warn(@"Ignoring failed test '%@'", description);
                else if (valid)
                    CAssert(NO, @"Expected '%@' to fail, but it passed", description);
                else
                    CAssert(NO, @"Expected '%@' to pass, but it failed: %@", description, error);
                }
        }
    }
}

TestCase(CBLJSONValidator) {
    // Tests that don't pass yet due to unimplemented functionality:
    kIgnoredTests = @[@"refRemote.json / change resolution scope / changed scope ref valid",
                      @"uniqueItems.json / uniqueItems validation / 1 and true are unique",
                      @"uniqueItems.json / uniqueItems validation / 0 and false are unique",
                      @"uniqueItems.json / uniqueItems validation / unique heterogeneous types are valid"];

    // Locate the test suite files via a relative path from this source file:
    NSString* dir = [[[[NSString alloc] initWithUTF8String: __FILE__] stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
    NSString* suiteDir = [dir stringByAppendingPathComponent: @"vendor/JSON-Schema-Test-Suite"];
    NSURL* baseRemoteURL = [NSURL URLWithString: @"http://localhost:1234/"];

    // Register some schemas for known URLs, to be used by the tests:
    NSString* remotesDir = [suiteDir stringByAppendingPathComponent: @"remotes"];
    NSArray* remotes = [[NSFileManager defaultManager] subpathsOfDirectoryAtPath: remotesDir error: nil];
    CAssert(remotes != nil, @"No test-suite remotes at %@", remotesDir);
    for (NSString* remoteName in remotes) {
        if ([remoteName hasSuffix: @".json"]) {
            NSURL* remoteURL = [baseRemoteURL URLByAppendingPathComponent: remoteName];
            [CBLJSONValidator registerSchema: loadJSONFile(remotesDir, remoteName)
                                      forURL: remoteURL];
        }
    }

    // Now load and run each test file:
    NSString* testsDir = [suiteDir stringByAppendingPathComponent: @"tests/draft4"];
    NSArray* tests = [[NSFileManager defaultManager] contentsOfDirectoryAtPath: testsDir error: nil];
    for (NSString* testName in tests) {
        if ([testName hasSuffix: @".json"])
            RunJSONSchemaTestFile(testName, loadJSONFile(testsDir, testName));
    }
}

#endif
#endif //DEBUG
