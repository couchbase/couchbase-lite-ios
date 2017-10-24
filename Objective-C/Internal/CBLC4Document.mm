//
//  CBLMutableDocumentData.mm
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/11/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLC4Document.h"

@implementation CBLC4Document {
    C4Document* _rawDoc;
}


+ (instancetype) document: (C4Document*)rawDoc {
    return [[self alloc] initWithRawDoc: rawDoc];
}


- (instancetype) initWithRawDoc: (C4Document*)rawDoc {
    self = [super init];
    if (self) {
        _rawDoc = rawDoc;
    }
    return self;
}


- (C4Document*) rawDoc {
    return _rawDoc;
}


- (C4DocumentFlags) flags {
    return _rawDoc->flags;
}


- (C4SequenceNumber) sequence {
    return _rawDoc->sequence;
}


- (C4String) revID {
    return _rawDoc->revID;
}


- (C4Revision) selectedRev {
    return _rawDoc->selectedRev;
}


- (void) dealloc {
    c4doc_free(_rawDoc);
}


@end
