//
//  CBLBase.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/9/15.
//  Copyright © 2015 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>


#if __has_feature(nullability)
#  ifndef NS_ASSUME_NONNULL_BEGIN
     // Xcode 6.3:
#    define NS_ASSUME_NONNULL_BEGIN _Pragma("clang assume_nonnull begin")
#    define NS_ASSUME_NONNULL_END   _Pragma("clang assume_nonnull end")
#  endif
#else
   // Xcode 6.2 and earlier:
#  define NS_ASSUME_NONNULL_BEGIN
#  define NS_ASSUME_NONNULL_END
#  define nullable
#  define __nullable
#endif


#if __has_feature(objc_generics)
#define CBLArrayOf(VALUE) NSArray<VALUE>
#define CBLDictOf(KEY, VALUE) NSDictionary<KEY, VALUE>
#define CBLEnumeratorOf(VALUE) NSEnumerator<VALUE>
#else
#define CBLArrayOf(VALUE) NSArray
#define CBLDictOf(KEY, VALUE) NSDictionary
#define CBLEnumeratorOf(VALUE) NSEnumerator
#endif

typedef CBLDictOf(NSString*, id) CBLJSONDict;
