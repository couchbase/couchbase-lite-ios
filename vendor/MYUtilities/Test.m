//
//  Test.m
//  MYUtilities
//
//  Created by Jens Alfke on 1/5/08.
//  Copyright 2008 Jens Alfke. All rights reserved.
//

#import "Test.h"

#if DEBUG

#import "ExceptionUtils.h"

BOOL gRunningTestCase;

struct TestCaseLink *gAllTestCases;
static int sPassed, sFailed;
static NSMutableArray* sFailedTestNames;
static int sCurTestCaseExceptions;


static void TestCaseExceptionReporter( NSException *x ) {
    sCurTestCaseExceptions++;
    fflush(stderr);
    Log(@"XXX FAILED test case -- backtrace:\n%@\n\n", x.my_callStack);
}

static void RecordFailedTest( struct TestCaseLink *test ) {
    if (!sFailedTestNames)
        sFailedTestNames = [[NSMutableArray alloc] init];
    [sFailedTestNames addObject: [NSString stringWithUTF8String: test->name]];
}

static BOOL RunTestCase( struct TestCaseLink *test )
{
    BOOL oldLogging = EnableLog(YES);
    gRunningTestCase = YES;
    if( test->testptr ) {
        NSAutoreleasePool *pool = [NSAutoreleasePool new];
        Log(@"=== Testing %s ...",test->name);
        @try{
            sCurTestCaseExceptions = 0;
            MYSetExceptionReporter(&TestCaseExceptionReporter);

            test->testptr();    //SHAZAM!
            
            if( sCurTestCaseExceptions == 0 ) {
                Log(@"√√√ %s passed\n\n",test->name);
                test->passed = YES;
                sPassed++;
            } else {
                Log(@"XXX FAILED test case '%s' due to %i exception(s) already reported above",
                    test->name,sCurTestCaseExceptions);
                sFailed++;
                RecordFailedTest(test);
            }
        }@catch( NSException *x ) {
            if( [x.name isEqualToString: @"TestCaseSkipped"] )
                Log(@"... skipping test %s since %@\n\n", test->name, x.reason);
            else {
                fflush(stderr);
                Log(@"XXX FAILED test case '%s' due to:\nException: %@\n%@\n\n", 
                      test->name,x,x.my_callStack);
                sFailed++;
                RecordFailedTest(test);
            }
        }@finally{
            [pool drain];
            test->testptr = NULL;       // prevents test from being run again
        }
    }
    gRunningTestCase = NO;
    EnableLog(oldLogging);
    return test->passed;
}


static BOOL RunTestCaseNamed( const char *name )
{
    for( struct TestCaseLink *test = gAllTestCases; test; test=test->next )
        if( strcmp(name,test->name)==0 ) {
            return RunTestCase(test);
        }
    Log(@"... WARNING: Could not find test case named '%s'\n\n",name);
    return NO;
}


void _RequireTestCase( const char *name )
{
    if( ! RunTestCaseNamed(name) ) {
        [NSException raise: @"TestCaseSkipped" 
                    format: @"prerequisite %s failed", name];
    }
}


void RunTestCases( int argc, const char **argv )
{
    sPassed = sFailed = 0;
    sFailedTestNames = nil;
    BOOL stopAfterTests = NO;
    for( int i=1; i<argc; i++ ) {
        const char *arg = argv[i];
        if( strncmp(arg,"Test_",5)==0 ) {
            arg += 5;
            if( strcmp(arg,"Only")==0 )
                stopAfterTests = YES;
            else if( strcmp(arg,"All") == 0 ) {
                for( struct TestCaseLink *link = gAllTestCases; link; link=link->next )
                    RunTestCase(link);
            } else {
                RunTestCaseNamed(arg);
            }
        }
    }
    if( sPassed>0 || sFailed>0 || stopAfterTests ) {
        NSAutoreleasePool *pool = [NSAutoreleasePool new];
        if( sFailed==0 )
            AlwaysLog(@"√√√√√√ ALL %i TESTS PASSED √√√√√√", sPassed);
        else {
            Warn(@"****** %i of %i TESTS FAILED: %@ ******", 
                 sFailed, sPassed+sFailed,
                 [sFailedTestNames componentsJoinedByString: @", "]);
            exit(1);
        }
        if( stopAfterTests ) {
            Log(@"Stopping after tests ('Test_Only' arg detected)");
            exit(0);
        }
        [pool drain];
    }
    [sFailedTestNames release];
    sFailedTestNames = nil;
}


#endif // DEBUG


#pragma mark -
#pragma mark ASSERTION FAILURE HANDLER:


void _AssertFailed( id rcvr, const void *selOrFn, const char *sourceFile, int sourceLine,
                    const char *condString, NSString *message, ... )
{
    if( message ) {
        va_list args;
        va_start(args,message);
        message = [[[NSString alloc] initWithFormat: message arguments: args] autorelease];
        message = [@"Assertion failed: " stringByAppendingString: message];
        va_end(args);
    } else
        message = [NSString stringWithUTF8String: condString];
    
    Log(@"*** ASSERTION FAILED: %@ ... NOT!", message);
    
    if( rcvr )
        [[NSAssertionHandler currentHandler] handleFailureInMethod: (SEL)selOrFn
                                                            object: rcvr 
                                                              file: [NSString stringWithUTF8String: sourceFile]
                                                        lineNumber: sourceLine 
                                                       description: @"%@", message];
    else
        [[NSAssertionHandler currentHandler] handleFailureInFunction: [NSString stringWithUTF8String:selOrFn]
                                                                file: [NSString stringWithUTF8String: sourceFile]
                                                          lineNumber: sourceLine 
                                                         description: @"%@", message];
    abort(); // unreachable, but appeases compiler
}


void _AssertAbstractMethodFailed( id rcvr, SEL cmd)
{
    [NSException raise: NSInternalInconsistencyException 
                format: @"Class %@ forgot to implement abstract method %@",
                         [rcvr class], NSStringFromSelector(cmd)];
    abort(); // unreachable, but appeases compiler
}


/*
 Copyright (c) 2008, Jens Alfke <jens@mooseyard.com>. All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification, are permitted
 provided that the following conditions are met:
 
 * Redistributions of source code must retain the above copyright notice, this list of conditions
 and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright notice, this list of conditions
 and the following disclaimer in the documentation and/or other materials provided with the
 distribution.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR
 IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND 
 FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRI-
 BUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR 
  PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN 
 CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF 
 THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */
