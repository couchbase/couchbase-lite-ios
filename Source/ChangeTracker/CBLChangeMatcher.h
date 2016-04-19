//
//  CBLChangeMatcher.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/8/15.
//  Copyright (c) 2014-2015 Couchbase, Inc. All rights reserved.
//

#import "CBLJSONReader.h"
@class CBL_RevID;


typedef void (^CBLChangeMatcherClient)(id sequence,
                                       NSString* docID,
                                       NSArray<CBL_RevID*>* revs,
                                       bool deleted);


@interface CBLChangeMatcher : CBLJSONDictMatcher
+ (CBLJSONMatcher*) changesFeedMatcherWithClient: (CBLChangeMatcherClient)client
                               expectWrapperDict: (BOOL)expectWrapperDict;
@end


