//
//  CBLReadOnlyFragment.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLReadOnlyArrayFragment.h"
#import "CBLReadOnlyDictionaryFragment.h"
@class CBLBlob;
@class CBLReadOnlyArray;
@class CBLReadOnlySubdocument;
@class CBLReadOnlyFragment;

NS_ASSUME_NONNULL_BEGIN

@protocol CBLReadOnlyFragment <NSObject>

@property (nonatomic, readonly) NSInteger integerValue;

@property (nonatomic, readonly) float floatValue;

@property (nonatomic, readonly) double doubleValue;

@property (nonatomic, readonly) BOOL boolValue;

@property (nonatomic, readonly, nullable) NSObject* object;

@property (nonatomic, readonly, nullable) NSString* string;

@property (nonatomic, readonly, nullable) NSNumber* number;

@property (nonatomic, readonly, nullable) NSDate* date;

@property (nonatomic, readonly, nullable) CBLBlob* blob;

@property (nonatomic, readonly, nullable) CBLReadOnlyArray* array;

@property (nonatomic, readonly, nullable) CBLReadOnlySubdocument* subdocument;

@property (nonatomic, readonly, nullable) NSObject* value;

@property (nonatomic, readonly) BOOL exists;

@end

@interface CBLReadOnlyFragment : NSObject <CBLReadOnlyFragment, CBLReadOnlyDictionaryFragment,
                                           CBLReadOnlyArrayFragment>

@end

NS_ASSUME_NONNULL_END
