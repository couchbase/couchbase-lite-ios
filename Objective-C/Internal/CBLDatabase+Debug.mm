//
//  CBLDatabase+Debug.m
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

#import "c4.h"
#import "fleece/Fleece.hh"
#import "CBLDocBranchIterator.h"
#import "CBLCoreBridge.h"
#import "CBLDatabase+Debug.h"
#import "CBLDatabase+Internal.h"
#import "CBLStatus.h"
#import "CBLStringBytes.h"

NS_ASSUME_NONNULL_BEGIN

@interface CBLRevTree: NSObject

- (instancetype) init;

- (NSMutableArray*) objectForKeyedSubscript: (NSString*)parentRevID;

@end

NS_ASSUME_NONNULL_END

@implementation CBLDatabase (Debug)

- (void) printRevsForDocumentID: (NSString*)documentID {
    C4Error err;
    CBLStringBytes bDocID(documentID);
    C4Document* doc = c4doc_get(self.c4db, bDocID, true, &err);
    if (!doc) {
        if (err.domain == LiteCoreDomain && err.code == kC4ErrorNotFound)
            NSLog(@"Error: Document \"%@\" not found", documentID);
        else
            NSLog(@"Error: Reading Document \"%@\": %d/%d", documentID, err.domain, err.code);
        return;
    }
    
    NSMutableString* docInfo = [NSMutableString string];
    if (doc->flags & kDocDeleted)
        [docInfo appendString: @", Deleted"];
    if (doc->flags & kDocConflicted)
        [docInfo appendString: @", Conflicted"];
    if (doc->flags & kDocHasAttachments)
        [docInfo appendString: @", Has Attachments"];
    NSLog(@"Document \"%@\"%@ (%@)", documentID, docInfo, self.name);
    
    // Remote IDs:
    NSMutableArray<NSString*>* remotes = [NSMutableArray array];
    for (C4RemoteID remoteID = 1; true; ++remoteID) {
        C4SliceResult revID = c4doc_getRemoteAncestor(doc, remoteID);
        if (revID.buf == NULL)
            break;
        [remotes addObject: sliceResult2string(revID)];
    }
    
    // RevTree tree;
    CBLRevTree* tree = [[CBLRevTree alloc] init];
    int maxDepth = 0;
    int maxRevIDLen = 0;
    for (CBLDocBranchIterator i(doc); i; ++i) {
        int depth = 1;
        NSString* childRevID = slice2string(doc->selectedRev.revID);
        maxRevIDLen = MAX(maxRevIDLen, (int)childRevID.length);
        while (c4doc_selectParentRevision(doc)) {
            NSString* parentRevID = slice2string(doc->selectedRev.revID);
            [tree[parentRevID] addObject: childRevID];
            childRevID = parentRevID;
            maxRevIDLen = MAX(maxRevIDLen, (int)childRevID.length);
            ++depth;
        }
        
        // Root:
        [tree[@""] addObject: childRevID];
        maxDepth = MAX(maxDepth, depth);
    }
    
    int metaColumnPos = 2 * maxDepth + maxRevIDLen + 4;
    writeChildren(doc, tree, remotes, @"", metaColumnPos, 1);
    
    for (C4RemoteID i = 1; i <= remotes.count; ++i) {
        fleece::alloc_slice addr(c4db_getRemoteDBAddress(self.c4db, i));
        if (!addr)
            break;
        NSLog(@"[REMOTE#%d] = %@", i, slice2string(addr));
    }
}

static void writeRevInfo(C4Document *doc, CBLRevTree* tree, NSArray* remotes,
                         NSString* rootRevID, int metaColumnPos, int indent) {
    C4Error err;
    CBLStringBytes bRootRevID(rootRevID);
    if (!c4doc_selectRevision(doc, bRootRevID, true, &err)) {
        NSLog(@"Error selecting revision: %d/%d", err.domain, err.code);
        return;
    }
    auto &rev = doc->selectedRev;
    
    NSMutableString* str = [NSMutableString string];
    [str appendString: string(indent, @" ")];
    [str appendString: @"* "];
    [str appendString: slice2string(rev.revID)];

    int pad = MAX(2, metaColumnPos - int(indent + 2 + rev.revID.size));
    [str appendString: string(pad, @" ")];

    if (rev.flags & kRevClosed)
        [str appendString: @"X"];
    else
        [str appendString: ((rev.flags & kRevDeleted)    ? @"D" : @"-")];
    [str appendString: ((rev.flags & kRevIsConflict)     ? @"C" : @"-")];
    [str appendString: ((rev.flags & kRevHasAttachments) ? @"A" : @"-")];
    [str appendString: ((rev.flags & kRevKeepBody)       ? @"K" : @"-")];
    [str appendString: ((rev.flags & kRevLeaf)           ? @"L" : @"-")];
    
    [str appendFormat: @" #%llu", rev.sequence];
    if (rev.body.buf)
        [str appendFormat: @", %zu bytes", rev.body.size];
    
    NSString* revID = slice2string(doc->revID);
    if ([rootRevID isEqualToString: revID])
        [str appendString: @"  [CURRENT]"];
    
    C4RemoteID i = 1;
    for (NSString* remote in remotes) {
        if ([remote isEqualToString: rootRevID])
            [str appendFormat: @"  [REMOTE#%d]", i];
        ++i;
    }
    
    NSLog(@"%@", str);
    
    writeChildren(doc, tree, remotes, rootRevID, metaColumnPos, indent+2);
}

static void writeChildren(C4Document *doc, CBLRevTree* tree, NSArray* remotes,
                          NSString* rootRevID, int metaColumnPos, int indent) {
    NSArray* children = tree[rootRevID];
    for (NSString* revID in children) {
       writeRevInfo(doc, tree, remotes, revID, metaColumnPos, indent);
    }
}

static NSString* string(int times, NSString* repeatString) {
    return [@"" stringByPaddingToLength: (repeatString.length * times)
                             withString: repeatString
                        startingAtIndex: 0];
}

@end

@implementation CBLRevTree {
    NSMutableDictionary* _tree;
}

- (instancetype) init {
    self = [super init];
    if (self) {
        _tree = [NSMutableDictionary dictionary];
    }
    return self;
}

- (NSMutableArray*) objectForKeyedSubscript: (NSString*)parentRevID {
    NSMutableArray* children = _tree[parentRevID];
    if (!children) {
        children = [NSMutableArray array];
        _tree[parentRevID] = children;
    }
    return children;
}

@end
