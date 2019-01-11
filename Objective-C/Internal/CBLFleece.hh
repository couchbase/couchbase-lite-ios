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
#import "fleece/Fleece.hh"
#import "MArray.hh"
#import "MDict.hh"

@class CBLDatabase, CBLC4Document;

NS_ASSUME_NONNULL_BEGIN


namespace cbl {

    // Returns true if newValue is different from oldValue. May return false positives.
    bool valueWouldChange(id newValue,
                          const fleece::MValue<id> &oldValue,
                          fleece::MCollection<id> &container);

    bool      asBool    (const fleece::MValue<id>&, const fleece::MCollection<id> &container);
    NSInteger asInteger (const fleece::MValue<id>&, const fleece::MCollection<id> &container);
    long long asLongLong(const fleece::MValue<id>&, const fleece::MCollection<id> &container);
    float     asFloat   (const fleece::MValue<id>&, const fleece::MCollection<id> &container);
    double    asDouble  (const fleece::MValue<id>&, const fleece::MCollection<id> &container);
    
    // Doc Context
    class DocContext : public fleece::MContext {
    public:
        DocContext(CBLDatabase *db, CBLC4Document* __nullable doc);
        
        CBLDatabase* database() const   {return _db;}
        CBLC4Document* __nullable document() const {return _doc;}
        NSMapTable* fleeceToNSStrings() const {return _fleeceToNSStrings;}
        
        id toObject(fleece::Value);
        
        private:
        CBLDatabase *_db;
        CBLC4Document* __nullable _doc;
        NSMapTable* _fleeceToNSStrings;
    };
}


@interface NSObject (CBLFleece)
@property (readonly, nonatomic) fleece::MCollection<id>* __nullable fl_collection;
@end


@interface CBLArray ()
{
    @protected
    fleece::MArray<id> _array;
}

- (instancetype) initWithMValue: (fleece::MValue<id>*)mv
                       inParent: (fleece::MCollection<id>*)parent;
- (instancetype) initWithCopyOfMArray: (const fleece::MArray<id>&)mArray
                            isMutable: (bool)isMutable;
@end


@interface CBLDictionary ()
{
    @protected
    fleece::MDict<id> _dict;
}

- (instancetype) initWithMValue: (fleece::MValue<id>*)mv
                       inParent: (fleece::MCollection<id>*)parent;
- (instancetype) initWithCopyOfMDict: (const fleece::MDict<id>&)mDict
                           isMutable: (bool)isMutable;
@end

NS_ASSUME_NONNULL_END
