
//
//  CBLCoreBridge.h
//  CouchbaseLite
//
//  Copyright (c) 2016 Couchbase, Inc All rights reserved.
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

#pragma once
#import <Foundation/Foundation.h>
#import "Fleece+CoreFoundation.h"
#import "c4.h"
#import "c4Document+Fleece.h"

NS_ASSUME_NONNULL_BEGIN

NSString* __nullable slice2string(C4Slice s);

C4Slice data2slice(NSData* __nullable);

// The sliceResult2... functions take care of freeing the C4SliceResult, or adopting its data.
NSData* __nullable   sliceResult2data(C4SliceResult);
NSString* __nullable sliceResult2string(C4SliceResult);
NSString* __nullable sliceResult2FilesystemPath(C4SliceResult);

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
