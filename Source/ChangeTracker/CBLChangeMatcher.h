//
//  CBLChangeMatcher.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/8/15.
//
//

#import "CBLJSONReader.h"


typedef void (^CBLChangeMatcherClient)(id sequence, NSString* docID, NSArray* revs, bool deleted);


@interface CBLChangeMatcher : CBLJSONDictMatcher
+ (CBLJSONMatcher*) changesFeedMatcherWithClient: (CBLChangeMatcherClient)client
                               expectWrapperDict: (BOOL)expectWrapperDict;
@end


