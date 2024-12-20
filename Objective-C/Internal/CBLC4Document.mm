//
//  CBLC4Document.mm
//  CouchbaseLite
//
//  Copyright (c) 2024 Couchbase, Inc All rights reserved.
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

#import "CBLC4Document.h"

@implementation CBLC4Document {
    C4Document* _rawDoc;
    FLDict _body;
}

+ (instancetype) document: (C4Document*)rawDoc {
    return [[self alloc] initWithRawDoc: rawDoc];
}

- (instancetype) initWithRawDoc: (C4Document*)rawDoc {
    self = [super init];
    if (self) {
        _rawDoc = rawDoc;
        _body = nullptr;
    }
    return self;
}

- (C4Document*) rawDoc {
    return _rawDoc;
}

- (C4RevisionFlags) revFlags {
    return _rawDoc->selectedRev.flags;
}

- (C4SequenceNumber) sequence {
    return _rawDoc->selectedRev.sequence;
}

- (C4String) docID {
    return _rawDoc->docID;
}

- (C4String) revID {
    return _rawDoc->selectedRev.revID;
}

- (FLDict) body {
    FLDict oBody = _body;
    _body = FLDict_Retain(c4doc_getProperties(_rawDoc));
    FLDict_Release(oBody);
    return _body;
}

- (void) dealloc {
    FLDict_Release(_body);
    c4doc_release(_rawDoc);
}

@end
