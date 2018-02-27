//
//  CBLFleece.hh
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import <Foundation/Foundation.h>
#import "CBLMutableArray.h"
#import "CBLMutableDictionary.h"
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


@interface CBLArray ()
{
    @protected
    fleeceapi::MArray<id> _array;
}

- (instancetype) initWithMValue: (fleeceapi::MValue<id>*)mv
                       inParent: (fleeceapi::MCollection<id>*)parent;
- (instancetype) initWithCopyOfMArray: (const fleeceapi::MArray<id>&)mArray
                            isMutable: (bool)isMutable;
@end


@interface CBLDictionary ()
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
