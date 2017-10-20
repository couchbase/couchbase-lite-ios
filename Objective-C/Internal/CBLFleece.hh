//
//  CBLFleece.hh
//  CouchbaseLite
//
//  Created by Jens Alfke on 10/11/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLArray.h"
#import "CBLDictionary.h"
#import "FleeceCpp.hh"
#import "MArray.hh"
#import "MDict.hh"

@class CBLDatabase, CBLC4Document;

NS_ASSUME_NONNULL_BEGIN


namespace cbl {

    // Returns true if newValue is different from oldValue. May return false positives.
    bool valueWouldChange(id newValue,
                          const fleeceapi::MValue<id> &oldValue,
                          fleeceapi::MCollection<id> &container);

    bool      asBool    (const fleeceapi::MValue<id>&, const fleeceapi::MCollection<id> &container);
    NSInteger asInteger (const fleeceapi::MValue<id>&, const fleeceapi::MCollection<id> &container);
    long long asLongLong(const fleeceapi::MValue<id>&, const fleeceapi::MCollection<id> &container);
    float     asFloat   (const fleeceapi::MValue<id>&, const fleeceapi::MCollection<id> &container);
    double    asDouble  (const fleeceapi::MValue<id>&, const fleeceapi::MCollection<id> &container);
    
    class DocContext : public fleeceapi::MContext {
    public:
        DocContext(CBLDatabase *db, CBLC4Document* __nullable doc);

        CBLDatabase* database() const   {return _db;}
        CBLC4Document* __nullable document() const {return _doc;}
        NSMapTable* fleeceToNSStrings() const {return _fleeceToNSStrings;}

        id toObject(fleeceapi::Value);

    private:
        CBLDatabase *_db;
        CBLC4Document* _doc;
        NSMapTable* _fleeceToNSStrings;
    };

}


@interface NSObject (CBLFleece)
@property (readonly, nonatomic) fleeceapi::MCollection<id>* __nullable fl_collection;
@end


@interface CBLReadOnlyArray ()
{
    @protected
    fleeceapi::MArray<id> _array;
}

- (instancetype) initWithMValue: (fleeceapi::MValue<id>*)mv
                       inParent: (fleeceapi::MCollection<id>*)parent;
- (instancetype) initWithCopyOfMArray: (const fleeceapi::MArray<id>&)mArray
                            isMutable: (bool)isMutable;
@end


@interface CBLReadOnlyDictionary ()
{
    @protected
    fleeceapi::MDict<id> _dict;
}

- (instancetype) initWithMValue: (fleeceapi::MValue<id>*)mv
                       inParent: (fleeceapi::MCollection<id>*)parent;
- (instancetype) initWithCopyOfMDict: (const fleeceapi::MDict<id>&)mDict
                           isMutable: (bool)isMutable;
@end

NS_ASSUME_NONNULL_END
