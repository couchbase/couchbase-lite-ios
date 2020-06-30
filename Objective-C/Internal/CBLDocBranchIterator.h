//
//  CBLDocBranchIterator.h
//  CouchbaseLite
//
//  Copyright (c) 2020 Couchbase, Inc All rights reserved.
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
#import "fleece/Fleece.hh"
#import "c4.h"

NS_ASSUME_NONNULL_BEGIN

class CBLDocBranchIterator {
public:
    CBLDocBranchIterator(C4Document *doc)
    :_doc(doc)
    {
        c4doc_selectCurrentRevision(doc);
        _branchID = _doc->selectedRev.revID;
    }

    operator bool() const {
        return _branchID != fleece::nullslice;
    }

    CBLDocBranchIterator& operator++() {
        c4doc_selectRevision(_doc, _branchID, false, nullptr);
        _branchID = fleece::nullslice;
        while (c4doc_selectNextRevision(_doc)) {
            if (_doc->selectedRev.flags & kRevLeaf) {
                _branchID = _doc->selectedRev.revID;
                break;
            }
        }
        return *this;
    }

private:
    C4Document* _doc;
    fleece::alloc_slice _branchID;
};

NS_ASSUME_NONNULL_END
