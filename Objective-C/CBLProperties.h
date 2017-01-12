//
//  CBLProperties.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 12/29/16.
//  Copyright © 2016 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLSubdocument;

/** CBLProperties defines interface for document property accessors. */
@protocol CBLProperties <NSObject>

NS_ASSUME_NONNULL_BEGIN

@property (readwrite, nullable, nonatomic) NSDictionary* properties;

- (BOOL)               booleanForKey:      (NSString*)key;
- (nullable NSDate*)   dateForKey:         (NSString*)key;
- (double)             doubleForKey:       (NSString*)key;
- (float)              floatForKey:        (NSString*)key;
- (NSInteger)          integerForKey:      (NSString*)key;
- (nullable id)        objectForKey:       (NSString*)key;
- (nullable NSString*) stringForKey:       (NSString*)key;

- (void) setBoolean: (BOOL)value                         forKey: (NSString*)key;
- (void) setDouble:  (double)value                       forKey: (NSString*)key;
- (void) setFloat:   (float)value                        forKey: (NSString*)key;
- (void) setInteger: (NSInteger)value                    forKey: (NSString*)key;
- (void) setObject:  (nullable id)value                  forKey: (NSString*)key;

- (nullable id) objectForKeyedSubscript: (NSString*)key;
- (void) setObject: (nullable id)value forKeyedSubscript: (NSString*)key;

- (void) removeObjectForKey: (NSString*)key;

- (BOOL) containsObjectForKey: (NSString*)key;

@end

/** Super class for CBLDocument and CBLSubdocument that implements CBLProperties protocol to
 provide property accessors. */
@interface CBLProperties: NSObject <CBLProperties>
@end

NS_ASSUME_NONNULL_END

// TODO:
// 1. Evaluate get/set Array of a specific type (new API)
// 2. Subdocument (In progress)
// 3. Blob (Need design)
// 4. Property complex object (Can be deferred)
// 5. Iterable or ObjC Equivalent (Can be deferred)
