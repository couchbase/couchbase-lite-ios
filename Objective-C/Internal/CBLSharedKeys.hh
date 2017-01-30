//
//  CBLSharedKeys.hh
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/29/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "c4Document+Fleece.h"
#import "Fleece+CoreFoundation.h"

NS_ASSUME_NONNULL_BEGIN

namespace cbl {

    class SharedKeys {
    public:
        SharedKeys()                                { }
        SharedKeys(C4Database* db)                  :_sharedKeys(c4db_getFLSharedKeys(db)) { }
        SharedKeys(const SharedKeys &sk, FLDict root)     :SharedKeys(sk) { useDocumentRoot(root); }

        SharedKeys(const SharedKeys &sk)            :_sharedKeys(sk._sharedKeys) { }
        SharedKeys& operator= (const SharedKeys &sk) noexcept;

        void useDocumentRoot(FLDict);

        id __nullable valueToObject(FLValue __nullable value) {
            return FLValue_GetNSObject(value, _sharedKeys, _documentStrings);
        }

        FLValue getDictValue(FLDict __nullable dict, FLSlice key) {
            return FLDict_GetSharedKey(dict, key, _sharedKeys);
        }

        NSString* getDictIterKey(FLDictIterator* iter) {
            return FLDictIterator_GetKeyAsNSString(iter, _documentStrings, _sharedKeys);
        }

    private:
        FLSharedKeys __nullable _sharedKeys {nullptr};
        NSMapTable* __nullable  _documentStrings {nil};
        FLDict __nullable       _root {nullptr};
    };

}


static inline id FLValue_GetNSObject(FLValue __nullable value, cbl::SharedKeys *sk) {
    return sk->valueToObject(value);
}

static inline FLValue FLDict_GetSharedKey(FLDict __nullable dict, FLSlice key, cbl::SharedKeys *sk) {
    return sk->getDictValue(dict, key);
}

static inline NSString* FLDictIterator_GetKey(FLDictIterator *iter, cbl::SharedKeys *sk) {
    return sk->getDictIterKey(iter);
}

NS_ASSUME_NONNULL_END
