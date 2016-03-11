//
//  CBLArrayDiff.m
//  Mutant
//
//  Created by Jens Alfke on 3/8/16.
//  Copyright © 2016 Couchbase. All rights reserved.
//

#import "CBLArrayDiff.h"
#include "Differ.hh"
#include <map>


namespace couchbase {
    namespace differ {

        class ArrayDiffer : public BaseDiffer {
        public:
            ArrayDiffer(NSArray *old, NSArray* nuu, CBLDiffItemComparator comparator)
            :_old(old),
            _nuu(nuu),
            _comparator(comparator)
            {
                setup(old.count, nuu.count);
            }

            std::map<size_t,size_t> modifiedIndexes;

        protected:
            virtual bool itemsEqual(size_t oldPos, size_t newPos) const {
                CBLDiffItemComparison c = _comparator(_old[oldPos], _nuu[newPos]);
                if (c == kCBLItemsModified)
                    const_cast<ArrayDiffer*>(this)->modifiedIndexes[oldPos] = newPos;
                return c != kCBLItemsDifferent;
            }

        private:
            NSArray *_old, *_nuu;
            CBLDiffItemComparator _comparator;
        };

    }
}

using namespace couchbase::differ;



@implementation CBLArrayDiff
{
    CBLDiffItemComparator _comparator;
    std::vector<CBLMovedRange> _moves;
    std::map<size_t,size_t> _modifiedIndexes;
}

@synthesize deletedIndexes=_deletedIndexes, insertedIndexes=_insertedIndexes;
@synthesize changedIndexesBefore=_changedIndexesBefore, changedIndexesAfter=_changedIndexesAfter;


- (instancetype) initWithBeforeArray: (NSArray*)beforeArray
                          afterArray: (NSArray*)afterArray
                         detectMoves: (BOOL)detectMoves
                      itemComparator: (CBLDiffItemComparator)comparator
{
    self = [super init];
    if (self) {

        try {
            if (!comparator)
                comparator = ^(id old, id nuu) {
                    return [old isEqual: nuu] ? kCBLItemsEqual : kCBLItemsDifferent;
                };
            ArrayDiffer d(beforeArray, afterArray, comparator);
            d.setDetectsMoves(detectMoves);
            auto changeVector = d.changes();

            NSMutableIndexSet* deletions = [NSMutableIndexSet new];
            NSMutableIndexSet* changesBefore = [NSMutableIndexSet new];
            NSMutableIndexSet* changesAfter = [NSMutableIndexSet new];
            NSMutableIndexSet* insertions = [NSMutableIndexSet new];
            for (auto ch = changeVector.begin(); ch != changeVector.end(); ++ch) {
                switch (ch->op) {
                    case del:
                        [deletions addIndex: ch->oldPos];
                        break;
                    case sub:
                        [changesBefore addIndex: ch->oldPos];
                        [changesAfter addIndex: ch->newPos];
                        break;
                    case ins:
                        [insertions addIndex: ch->newPos];
                        break;
                    case mov:
                        // Add this move to the latest CBLMovedRange if it fits into it:
                        if (!_moves.empty()) {
                            CBLMovedRange &m = _moves.back();
                            if (ch->oldPos == NSMaxRange(m.before) &&
                                    ch->newPos-ch->oldPos == m.afterLocation-m.before.location) {
                                m.before.length++;
                                break;
                            }
                        }
                        _moves.push_back({{ch->oldPos, 1}, ch->newPos});
                        break;
                    default:
                        break;
                }
            }
            _deletedIndexes = deletions;
            _changedIndexesBefore = changesBefore;
            _changedIndexesAfter = changesAfter;
            _insertedIndexes = insertions;
            _modifiedIndexes = d.modifiedIndexes;
            NSLog(@"CBLArrayDiff: %lu deleted, %lu replaced, %lu inserted, %lu moved, %lu modified",
                  (unsigned long)deletions.count, (unsigned long)changesBefore.count,
                  (unsigned long)insertions.count, _moves.size(), _modifiedIndexes.size());
            std::cerr << changeVector << "\n";
        } catch (const std::exception &x) {
            NSLog(@"ERROR: CBLArrayDiff failed with C++ exception: %s", x.what());
            return nil;
        } catch (...) {
            NSLog(@"ERROR: CBLArrayDiff failed with unknown exception");
            return nil;
        }
    }
    return self;
}


- (NSUInteger) moveCount {
    return _moves.size();
}

- (const CBLMovedRange*) movedRanges {
    return _moves.data();
}


- (void) forEachModification: (void (^)(NSUInteger before, NSUInteger after))block {
    for (auto i = _modifiedIndexes.begin(); i != _modifiedIndexes.end(); ++i)
        block(i->first, i->second);
}


- (void) forEachMove: (void (^)(NSUInteger before, NSUInteger after))block {
    for (auto m = _moves.begin(); m != _moves.end(); ++m) {
        for (NSUInteger i = 0; i < m->before.length; i++) {
            block(m->before.location + i, m->afterLocation + i);
        }
    }
}


+ (NSArray*) indexPathsForSet: (NSIndexSet*)set withSection: (NSUInteger)section;
{
    if (!set)
        return nil;
    NSUInteger path[2] = {section, 0};
    NSMutableArray* paths = [NSMutableArray arrayWithCapacity: set.count];
    for (NSUInteger i = set.firstIndex; i != NSNotFound; i = [set indexGreaterThanIndex: i]) {
        path[1] = i;
        [paths addObject: [[NSIndexPath alloc] initWithIndexes: path length: 2]];
    }
    return paths;
}


@end
