//
//  CBLFragment.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLArray.h"
#import "CBLArrayFragment.h"
#import "CBLDictionaryFragment.h"
#import "CBLReadOnlyFragment.h"
#import "CBLSubdocument.h"

NS_ASSUME_NONNULL_BEGIN

@protocol CBLFragment <CBLReadOnlyFragment>

@property (nonatomic, nullable) NSObject* value;

@property (nonatomic, readonly, nullable) CBLArray* array;

@property (nonatomic, readonly, nullable) CBLSubdocument* subdocument;

@end

@interface CBLFragment : CBLReadOnlyFragment <CBLFragment, CBLDictionaryFragment, CBLArrayFragment>

@end

NS_ASSUME_NONNULL_END
