//
//  CBLSharedKeys.hh
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/29/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#pragma once
#import <Foundation/Foundation.h>
#import "c4Document+Fleece.h"
#import "Fleece+CoreFoundation.h"
#include <mutex>

NS_ASSUME_NONNULL_BEGIN

using namespace std;

namespace cbl {
    
    class SharedKeys {
        
    public:
        SharedKeys() { }
        SharedKeys(C4Database* db) :_sharedKeys(c4db_getFLSharedKeys(db)) { }
        SharedKeys& operator= (const SharedKeys &sk) noexcept;
        
        operator FLSharedKeys __nullable () const {
            return _sharedKeys;
        }
        
        id __nullable valueToObject(FLValue __nullable value) {
            CBL_LOCK_GUARD(_mutex);
            return FLValue_GetNSObject(value, _sharedKeys, nil);
        }
        
        FLValue __nullable getDictValue(FLDict __nullable dict, FLSlice key) {
            CBL_LOCK_GUARD(_mutex);
            return FLDict_GetSharedKey(dict, key, _sharedKeys);
        }
        
        NSString* __nullable getDictIterKey(FLDictIterator* iter) {
            CBL_LOCK_GUARD(_mutex);
            return FLDictIterator_GetKeyAsNSString(iter, nil, _sharedKeys);
        }
        
        bool encodeKey(FLEncoder encoder, FLSlice key) {
            // Optimization: We may create the lock() and unlock() func instead
            // to avoid locking on every encoding key/value.
            CBL_LOCK_GUARD(_mutex);
            return FLEncoder_WriteKey(encoder, key);
        }
        
        bool encodeValue(FLEncoder encoder, FLValue __nullable value) {
            // Optimization: We may create the lock() and unlock() func instead
            // to avoid locking on every encoding key/value.
            CBL_LOCK_GUARD(_mutex);
            return FLEncoder_WriteValueWithSharedKeys(encoder, value, _sharedKeys);
        }
        
        bool containBlob(FLDict dict) {
            CBL_LOCK_GUARD(_mutex);
            return c4doc_dictContainsBlobs(dict, _sharedKeys);
        }
        
    private:
        FLSharedKeys __nullable _sharedKeys {nullptr};
        mutex                   _mutex;
    };
    
}


static inline id __nullable
FLValue_GetNSObject(FLValue __nullable value, cbl::SharedKeys *sk) {
    return sk->valueToObject(value);
}

static inline FLValue __nullable
FLDict_GetValue(FLDict __nullable dict, FLSlice key, cbl::SharedKeys *sk) {
    return sk->getDictValue(dict, key);
}

static inline NSString* __nullable
FLDictIterator_GetKey(FLDictIterator *iter, cbl::SharedKeys *sk) {
    return sk->getDictIterKey(iter);
}

static inline bool
FL_WriteKey(FLEncoder encoder, FLSlice key, cbl::SharedKeys *sk) {
    return sk->encodeKey(encoder, key);
}

static inline bool
FL_WriteValue(FLEncoder encoder, FLValue __nullable value, cbl::SharedKeys *sk) {
    return sk->encodeValue(encoder, value);
}

static inline bool
C4Doc_ContainsBlobs(FLDict root, cbl::SharedKeys *sk) {
    return sk->containBlob(root);
}

NS_ASSUME_NONNULL_END

