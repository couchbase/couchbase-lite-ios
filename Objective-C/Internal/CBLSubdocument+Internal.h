//
//  CBLSubdocument+Internal.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/2/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//


#import "CBLSubdocument.h"
#import "CBLProperties.h"
#import "CBLInternal.h"


#ifdef __cplusplus
namespace cbl {
    class SharedKeys;
}
#endif

typedef void (^CBLOnMutateBlock)();


NS_ASSUME_NONNULL_BEGIN


@interface CBLSubdocument () <CBLJSONCoding>

@property (weak, nonatomic, nullable) id swiftSubdocument;

@property (weak, nonatomic, nullable) CBLProperties* parent;

@property (nonatomic, nullable) NSString* key;

#ifdef __cplusplus
- (instancetype) initWithParent: (nullable CBLProperties*)parent
                     sharedKeys: (cbl::SharedKeys)sharedKeys;
#endif

- (void) setOnMutate: (nullable CBLOnMutateBlock)onMutate;

- (void) invalidate;

@end


NS_ASSUME_NONNULL_END
