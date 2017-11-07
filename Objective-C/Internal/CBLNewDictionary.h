//
//  CBLNewDictionary.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 10/12/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLMutableDictionary.h"

NS_ASSUME_NONNULL_BEGIN


/** An implementation of a CBLMutableDictionary with no storage, i.e. that's just been added to a doc.
     This class is an optimization that does less work than the regular CBLMutableDictionary. */
@interface CBLNewDictionary : NSObject <CBLMutableDictionary>

- (instancetype) initWithDictionary: (NSDictionary*)dictionary;

@end

NS_ASSUME_NONNULL_END
