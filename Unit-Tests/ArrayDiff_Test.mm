//
//  ArrayDiff_Test.mm
//  CouchbaseLite
//
//  Created by Jens Alfke on 3/11/16.
//  Copyright © 2016 Couchbase, Inc. All rights reserved.
//

#import "CBLTestCase.h"
#import "Differ.hh"
#import "CBLArrayDiff.h"

using namespace couchbase::differ;


@interface ArrayDiff_Test : CBLTestCase
@end


static void test(ArrayDiff_Test *self,
                 const char *oldStr, const char *newStr,
                 ChangeVector expectedChanges,
                 const ChangeVector *expectedMovesP =NULL);
static void test(ArrayDiff_Test *self,
                 const char *oldStr, const char *newStr,
                 ChangeVector expectedChanges,
                 ChangeVector expectedMoves);


@implementation ArrayDiff_Test

- (void)testDiffer {
    // Simple edge cases:
    test(self, "", "",        {});
    test(self, "a", "a",      {});
    test(self, "", "a",       {{ins, 0, 0}});
    test(self, "a", "",       {{del, 0, 0}});
    test(self, "cat", "cat",  {});
    test(self, "cat", "",     { {del, 0, 0}, {del, 1, 0}, {del, 2, 0} });
    test(self, "", "cat",     { {ins, 0, 0}, {ins, 0, 1}, {ins, 0, 2} });

    test(self, "abC", "abZ",  { {sub, 2, 2} });
    test(self, "Abc", "Zbc",  { {sub, 0, 0} });
    test(self, "abc", "abcDEF",  { {ins, 3, 3}, {ins, 3, 4}, {ins, 3, 5} });
    test(self, "ABCdef", "def",  { {del, 0, 0}, {del, 1, 0}, {del, 2, 0} });

    // Unchanged prefix & suffix
    test(self, "aaaaabccccc", "aaaaadccccc",     { {sub, 5, 5} });

    // Single insertion/deletion
    test(self, "chat", "cht", {{del, 2, 2}});
    test(self, "cht", "chat", {{ins, 2, 2}});
    test(self, "chat", "chit",{{sub, 2, 2}});

    test(self, "cat", "ctx",  {{del, 1, 1}, {ins, 3, 2}});
    test(self, "cat", "cuts", {{sub, 1, 1}, {ins, 3, 3}});

    test(self, "chat", "qhitx", {{sub, 0, 0}, {sub, 2, 2}, {ins, 4, 4}});

    test(self, "abcdefghijklm", "nopqrstuvwxyz",
         { {sub, 0, 0}, {sub, 1, 1}, {sub, 2, 2}, {sub, 3, 3}, {sub, 4, 4}, {sub, 5, 5}, {sub, 6, 6}, {sub, 7, 7}, {sub, 8, 8}, {sub, 9, 9}, {sub, 10, 10}, {sub, 11, 11}, {sub, 12, 12} } );

    test(self, "abcdefghijklm", "nopqrsbtuvwxyz", { {sub, 0, 0}, {sub, 1, 1}, {sub, 2, 2}, {sub, 3, 3}, {sub, 4, 4}, {sub, 5, 5}, {sub, 6, 6}, {sub, 7, 7}, {sub, 8, 8}, {sub, 9, 9}, {sub, 10, 10}, {sub, 11, 11}, {sub, 12, 12}, {ins, 13, 13} });

    // Cases with moves:
    test(self, "cat", "tag",
         { {sub, 0, 0}, {sub, 2, 2} },
         { {mov, 2, 0}, {del, 0, 1}, {ins, 2, 2} });

    test(self, "edbgae", "eadgbe",
         { {ins, 1, 1}, {del, 2, 3}, {sub, 4, 4} },
         { {mov, 4, 1}, {mov, 2, 4} });

    test(self, "abCDefgh", "abefCDgh",
         { {del, 2, 2}, {del, 3, 2}, {ins, 6, 4}, {ins, 6, 5} },
         { {mov, 2, 4}, {mov, 3, 5} });
    test(self, "abCdefGh", "abGdefCh",
         { {sub, 2, 2}, {sub, 6, 6} },
         { {mov, 6, 2}, {mov, 2, 6} });

    test(self, "abcdefghijklm", "akcefghijlmd",
         { {sub, 1, 1}, {del, 3, 3}, {del, 10, 9}, {ins, 13, 11} },
         { {mov, 10, 1}, {del, 1, 2}, {mov, 3, 11} });

    test(self, "abcdefghijklm", "akceWXfghZbQVijPlmd",
         { {sub, 1, 1}, {del, 3, 3}, {ins, 5, 4}, {ins, 5, 5}, {ins, 8, 9}, {ins, 8, 10}, {ins, 8, 11}, {ins, 8, 12}, {sub, 10, 15}, {ins, 13, 18} },
         { {mov, 10, 1}, {ins, 5, 4}, {ins, 5, 5}, {ins, 8, 9}, {mov, 1, 10}, {ins, 8, 11}, {ins, 8, 12}, {ins, 10, 15}, {mov, 3, 18} });
}


- (void) testDifferScaling {
    std::cerr << "Diffing 2000 integers...\n";
    std::vector<int> old(2000);
    for (int i=0; i<2000; i++)
        old[i] = i;
    std::vector<int> nuu = old;
    nuu[0] = 2001;
    nuu[1999] = 2002;
    for (int i = 888; i < 1300; i++)
        nuu.insert(nuu.begin()+i, 2000+i);

    Differ<int> d(old, nuu);
    auto ops = d.changes();
    if (ops.size() < 100)
        std::cerr << "    " << ops << "\n";
#if DEBUG
    d.dump();
#endif
}


static NSString* toStr(NSIndexSet *set) {
    NSMutableString *str = [@"(" mutableCopy];
    [set enumerateRangesUsingBlock: ^(NSRange range, BOOL *stop) {
        if (str.length > 1)
            [str appendString: @", "];
        [str appendFormat: @"%lu", (unsigned long)range.location];
        if (range.length > 1)
            [str appendFormat: @"-%lu", (unsigned long)NSMaxRange(range)-1];
    }];
    [str appendString: @")"];
    return str;
}

static bool operator == (const CBLMovedRange &a, const CBLMovedRange &b) {
    return NSEqualRanges(a.before, b.before) && a.afterLocation == b.afterLocation;
}


- (void) testObjCArrayDiff {
    auto cmp = ^CBLDiffItemComparison(id old, id nuu) {
        if ([old isEqualToString: nuu])
            return kCBLItemsEqual;
        else if ([old caseInsensitiveCompare: nuu] == 0)
            return kCBLItemsModified;
        else
            return kCBLItemsDifferent;
    };
    NSArray* before = [@"a b c d e f g h i j k l m" componentsSeparatedByString: @" "];
    NSArray* after  = [@"a k c e W X f g h Z b Q V i j P l m d" componentsSeparatedByString: @" "];
    CBLArrayDiff* diff = [[CBLArrayDiff alloc] initWithBeforeArray: before
                                                        afterArray: after
                                                       detectMoves: NO
                                                    itemComparator: cmp];
    AssertEqual(toStr(diff.deletedIndexes), @"(3)");
    AssertEqual(toStr(diff.insertedIndexes),  @"(4-5, 9-12, 18)");
    AssertEqual(toStr(diff.changedIndexesBefore),  @"(1, 10)");
    AssertEqual(toStr(diff.changedIndexesAfter),  @"(1, 15)");

    before = [@"a b c D e f G H i j k l m" componentsSeparatedByString: @" "];
    after  = [@"a b f g i j k c d e l m" componentsSeparatedByString: @" "];
    diff = [[CBLArrayDiff alloc] initWithBeforeArray: before
                                          afterArray: after
                                         detectMoves: YES
                                      itemComparator: cmp];
    AssertEqual(toStr(diff.deletedIndexes), @"(7)");
    AssertEqual(toStr(diff.insertedIndexes),  @"()");
    AssertEq(diff.moveCount, 1u);
    Assert(diff.movedRanges[0] == (CBLMovedRange{{2, 3}, 7}));

    NSMutableDictionary* mods = [NSMutableDictionary dictionary];
    [diff forEachModification:^(NSUInteger before, NSUInteger after) {
        mods[@(before)] = @(after);
    }];
    AssertEqual(mods, (@{@3: @8, @6: @3}));
}



static void test(ArrayDiff_Test *self,
                 const char *oldStr, const char *newStr,
                 ChangeVector expectedChanges,
                 const ChangeVector *expectedMovesP)
{
    std::cerr << "'" << oldStr << "' --> '" << newStr << "'\n";

    std::vector<char> old(strlen(oldStr)), nuu(strlen(newStr));
    memcpy(old.data(), oldStr, strlen(oldStr));
    memcpy(nuu.data(), newStr, strlen(newStr));

    Differ<char> d(old, nuu);
    auto ops = d.changes();
    std::cerr << "    " << ops << "\n";

    if (ops != expectedChanges) {
        std::cerr << "*** " << expectedChanges << " EXPECTED ***\n";
        XCTFail(@"Wrong changes from Differ");
    }

    auto &expectedMoves = expectedMovesP ? *expectedMovesP : expectedChanges;
    d.setDetectsMoves(true);
    auto ops2 = d.changes();
    if (expectedMovesP || ops2 != expectedMoves) {
        std::cerr << "    " << ops2 << "\n";
    }
    Assert(verifyChanges(self, oldStr, newStr, ops));
    if (ops2 != expectedMoves) {
        std::cerr << "*** " << expectedMoves << " *** EXPECTED (moves)\n";
        XCTFail(@"Wrong moves from Differ");
    }
    //verifyChanges(oldStr, newStr, ops2);
#if DEBUG
    d.dump();
#endif
}


static void test(ArrayDiff_Test *self,
                 const char *oldStr, const char *newStr,
                 ChangeVector expectedChanges,
                 ChangeVector expectedMoves)
{
    test(self, oldStr, newStr, expectedChanges, &expectedMoves);
}


static bool verifyChanges(ArrayDiff_Test *self, const char *oldStr, const char *newStr, ChangeVector changes) {
    char buf[1000];
    strcpy(buf, oldStr);
    int offset = 0;
    for (auto ch = changes.begin(); ch != changes.end(); ++ch) {
        int pos = (int)ch->oldPos + offset;
        switch (ch->op) {
            case del: {
                Assert(pos >= 0 && pos < (int)strlen(buf));
                memmove(&buf[pos], &buf[pos+1], strlen(buf)-pos);
                --offset;
                break;
            }
            case ins: {
                Assert(pos >= 0 && pos <= (int)strlen(buf));
                memmove(&buf[pos]+1, &buf[pos], strlen(buf)-pos+1);
                buf[pos] = newStr[ch->newPos];
                ++offset;
                break;
            }
            case sub:
                Assert(pos >= 0 && pos < (int)strlen(buf));
                buf[pos] = newStr[ch->newPos];
                break;
            case mov:
                if (ch->oldPos < ch->newPos) { // move forward:
                    memmove(&buf[ch->oldPos], &buf[ch->oldPos+1], ch->newPos - ch->oldPos);
                    buf[ch->newPos] = oldStr[ch->newPos];
                    --offset;
                } else { // move backward:
                    memmove(&buf[ch->newPos+1], &buf[ch->newPos], ch->oldPos - ch->newPos);
                    buf[ch->newPos] = oldStr[ch->oldPos];
                    ++offset;
                }
                break;
            default:
                std::cerr << "*** Illegal op " << (int)ch->op << " ***\n";
                return false;
        }
    }
    if (strcmp(buf, newStr) == 0)
        return true;
    std::cerr << "*** Failed: Produced \"" << buf << "\" not \"" << newStr << "\" ***\n";
    return false;
}

@end