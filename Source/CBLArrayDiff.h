//
//  CBLArrayDiff.h
//  Mutant
//
//  Created by Jens Alfke on 3/8/16.
//  Copyright © 2016 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>


NS_ASSUME_NONNULL_BEGIN


typedef struct {
    NSRange before;             /** Range of indices in beforeArray */
    NSUInteger afterLocation;   /** Index moved to in afterArray */
} CBLMovedRange;


typedef NS_ENUM(uint8_t, CBLDiffItemComparison) {
    kCBLItemsDifferent = 0,     /**< These are two different items */
    kCBLItemsEqual,             /**< These are the same item, and it's unchanged */
    kCBLItemsModified           /**< These are the same item, but it's been modified */
};

/** Custom block type for deciding if two objects are the same item, and if so, whether the
    item has been modified. */
typedef CBLDiffItemComparison (^CBLDiffItemComparator)(id old, id nuu);


/** Computes the differences between two NSArrays, as a set of inserts, deletes, and
    substitutions of items (and optionally of moves too.) */
@interface CBLArrayDiff : NSObject

/** Initializes the CBLArrayDiff and runs the diff operation.
    @param beforeArray  The array of items before the change
    @param afterArray  The array of items after the change
    @param detectMoves  YES if move operations should be used, not just insertions/deletions
    @param itemComparator  An equality test for items from beforeArray and afterArray
    @return  The initialized object */
- (instancetype) initWithBeforeArray: (NSArray*)beforeArray
                          afterArray: (NSArray*)afterArray
                         detectMoves: (BOOL)detectMoves
                      itemComparator: (nullable CBLDiffItemComparator)itemComparator;

/** The indexes (in the old array) of all deleted items */
@property (readonly, nonatomic) NSIndexSet* deletedIndexes;

/** The indexes (in the old array) of all replaced items,
    i.e. the items being deleted to be replaced by new items. */
@property (readonly, nonatomic) NSIndexSet* changedIndexesBefore;

/** The indexes (in the new array) of all replaced items,
    i.e. the new items replacing deleted ones. */
@property (readonly, nonatomic) NSIndexSet* changedIndexesAfter;

/** The indexes (in the new array) of all replaced items */
@property (readonly, nonatomic) NSIndexSet* insertedIndexes;

/** The number of moved items */
@property (readonly, nonatomic) NSUInteger moveCount;

/** A C array of the moved items. */
@property (readonly, nonatomic) const CBLMovedRange* movedRanges;

//// CONVENIENCES:

/** Calls the block once for every modified item, giving its index in the before and after arrays. */
- (void) forEachModification: (void (^)(NSUInteger before, NSUInteger after))block;

/** Calls the block once for every moved item. */
- (void) forEachMove: (void (^)(NSUInteger before, NSUInteger after))block;

/** A convenience that converts the values of one of the above properties into an array of
    NSIndexPaths suitable for passing to UITableView methods like -deleteRowsAtIndexPaths: */
+ (NSArray*) indexPathsForSet: (NSIndexSet*)set
                  withSection: (NSUInteger)section;

@end


NS_ASSUME_NONNULL_END
