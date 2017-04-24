
//
//  CBLCoreBridge.h
//  CouchbaseLite
//
//  Source: https://github.com/couchbase/couchbase-lite-core/blob/master/Objective-C/LC_Internal.h
//  Created by Jens Alfke on 10/27/16.
//
//  Created by Pasin Suriyentrakorn on 12/30/16.
//  Copyright © 2016 Couchbase. All rights reserved.
//

#pragma once
#import <Foundation/Foundation.h>
#import "Fleece+CoreFoundation.h"
#import "c4.h"
#import "c4Document+Fleece.h"
#import "CBLSymmetricKey.h"

NS_ASSUME_NONNULL_BEGIN

NSString* slice2string(C4Slice s);

static inline NSString* slice2string(FLSlice s) {
    return slice2string(C4Slice{s.buf, s.size});
}

C4Slice data2slice(NSData*);

// The sliceResult2... functions take care of freeing the C4SliceResult, or adopting its data.
NSData*   sliceResult2data(C4SliceResult);
NSString* sliceResult2string(C4SliceResult);
NSString* sliceResult2FilesystemPath(C4SliceResult);

static inline NSString* sliceResult2string(FLSliceResult s) {
    return sliceResult2string(C4SliceResult{s.buf, s.size});
}

C4EncryptionKey symmetricKey2C4Key(CBLSymmetricKey* key);

class C4Transaction {
public:
    C4Transaction(C4Database *db)
    :_db(db)
    { }
    
    ~C4Transaction() {
        if (_active)
            c4db_endTransaction(_db, false, nullptr);
    }
    
    bool begin() {
        if (!c4db_beginTransaction(_db, &_error))
            return false;
        _active = true;
        return true;
    }
    
    bool end(bool commit) {
        NSCAssert(_active, @"Forgot to begin");
        _active = false;
        return c4db_endTransaction(_db, commit, &_error);
    }
    
    bool commit()               {return end(true);}
    bool abort()                {return end(false);}
    
    const C4Error &error()      {return _error;}
    
private:
    C4Database *_db;
    C4Error _error;
    bool _active;
};

NS_ASSUME_NONNULL_END
