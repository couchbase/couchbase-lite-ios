//
//  Test.h
//  MYUtilities
//
//  Created by Jens Alfke on 1/5/08.
//  Copyright 2008 Jens Alfke. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CollectionUtils.h"
#import "Logging.h"


/** Call this first thing in main() to run tests.
    This function is a no-op if the DEBUG macro is not defined (i.e. in a release build).
    At runtime, to cause a particular test "X" to run, add a command-line argument "Test_X".
    To run all tests, add the argument "Test_All".
    To run only tests without starting the main program, add the argument "Test_Only". */
#if DEBUG
void RunTestCases( int argc, const char **argv );
extern BOOL gRunningTestCase;
#else
#define RunTestCases(ARGC,ARGV)
#define gRunningTestCase NO
#endif

/** The TestCase() macro declares a test case.
    Its argument is a name for the test case (without quotes), and it's followed with a block
    of code implementing the test.
    The code should raise an exception if anything fails.
    The CAssert, CAssertEqual and CAssertEq macros, below, are the most useful way to do this.
    A test case can register a dependency on another test case by calling RequireTestCase().
    Example:
        TestCase(MyLib) {
            RequireTestCase("LibIDependOn");
            CAssertEq( myFunction(), 12345 );
        }
    Test cases are disabled if the DEBUG macro is not defined (i.e. in a release build). */
#if DEBUG
#define TestCase(NAME)      void Test_##NAME(void); \
                            struct TestCaseLink linkToTest##NAME = {&Test_##NAME,#NAME}; \
                            __attribute__((constructor)) static void registerTestCase##NAME() \
                                {linkToTest##NAME.next = gAllTestCases; gAllTestCases=&linkToTest##NAME; } \
                            void Test_##NAME(void)
#else
#define TestCase(NAME)      __attribute__((unused)) static void Test_##NAME(void)
#endif

/** Can call this in a test case to indicate a prerequisite.
    The prerequisite test will be run first, and if it fails, the current test case will be skipped. */
#if DEBUG
#define RequireTestCase(NAME)   _RequireTestCase(#NAME)
void _RequireTestCase( const char *name );
#else
#define RequireTestCase(NAME)
#endif


/** General-purpose assertions, replacing NSAssert etc.. You can use these outside test cases. */

#define Assert(COND,MSG...)    do{ if( __builtin_expect(!(COND),NO) ) { \
                                    IN_SEGMENT_NORETURN(Logging) {_AssertFailed(self,_cmd, __FILE__, __LINE__,\
                                                        #COND,##MSG,NULL);} } }while(0)
#define CAssert(COND,MSG...)    do{ if( __builtin_expect(!(COND),NO) ) { \
                                    static const char *_name = __PRETTY_FUNCTION__;\
                                    IN_SEGMENT_NORETURN(Logging) {_AssertFailed(nil, _name, __FILE__, __LINE__,\
                                                        #COND,##MSG,NULL);} } }while(0)

// AssertEqual is for Obj-C objects
#define AssertEqual(VAL,EXPECTED)   do{ id _val = VAL, _expected = EXPECTED;\
                                        Assert(_val==_expected || [_val isEqual: _expected], @"Unexpected value for %s: %@ (expected %@)", #VAL,_val,_expected); \
                                    }while(0)
#define CAssertEqual(VAL,EXPECTED)  do{ id _val = (VAL), _expected = (EXPECTED);\
                                        CAssert(_val==_expected || [_val isEqual: _expected], @"Unexpected value for %s: %@ (expected %@)", #VAL,_val,_expected); \
                                    }while(0)

// AssertEq is for scalars (int, float...)
#define AssertEq(VAL,EXPECTED)  do{ __typeof(VAL) _val = VAL; __typeof(EXPECTED) _expected = EXPECTED;\
                                    Assert(_val==_expected, @"Unexpected value for %s: %@ (expected %@)", #VAL,$object(_val),$object(_expected)); \
                                }while(0)
#define CAssertEq(VAL,EXPECTED) do{ __typeof(VAL) _val = VAL; __typeof(EXPECTED) _expected = EXPECTED;\
                                    CAssert(_val==_expected, @"Unexpected value for %s: %@ (expected %@)", #VAL,$object(_val),$object(_expected)); \
                                }while(0)

#define AssertNil(VAL)          AssertEq((VAL),nil)
#define CAssertNil(VAL)         CAssertEq((VAL),(id)nil)  // ARC is picky about the type of nil here
#define CAssertNull(VAL)        CAssertEq((VAL),NULL)

#define AssertAbstractMethod()  _AssertAbstractMethodFailed(self,_cmd);

// Nasty internals ...
#if DEBUG
void _RunTestCase( void (*testptr)(), const char *name );

struct TestCaseLink {void (*testptr)(); const char *name; BOOL passed; struct TestCaseLink *next;};
extern struct TestCaseLink *gAllTestCases;
#endif // DEBUG
void _AssertFailed( id rcvr, const void *selOrFn, const char *sourceFile, int sourceLine,
                   const char *condString, NSString *message, ... ) __attribute__((noreturn));
void _AssertAbstractMethodFailed( id rcvr, SEL cmd) __attribute__((noreturn));
