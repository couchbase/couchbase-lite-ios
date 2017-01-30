//
//  CBLSharedKeys.mm
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/29/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLSharedKeys.hh"
#import "CBLCoreBridge.h"
#import "Fleece.h"
#import "Fleece+CoreFoundation.h"


namespace cbl {

    SharedKeys& SharedKeys::operator= (const SharedKeys &sk) noexcept {
        _sharedKeys = sk._sharedKeys;
        _documentStrings = nil;
        _root = nullptr;
        return *this;
    }

    void SharedKeys::useDocumentRoot(FLDict root) {
        if (root != _root) {
            _root = root;
            _documentStrings = root ? FLCreateSharedStringsTable() : nullptr;
        }
    }
}
