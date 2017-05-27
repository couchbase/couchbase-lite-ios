//
//  CBLStatus.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/2/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#pragma once
#import <Foundation/Foundation.h>
#import "Fleece.h"
#import "c4.h"

NS_ASSUME_NONNULL_BEGIN

typedef enum {
    kCBLStatusForbidden = 403,
    kCBLStatusNotFound = 404
} CBLStatus;

BOOL convertError(const C4Error &error, NSError* _Nullable * outError);

BOOL convertError(const FLError &error, NSError* _Nullable * outError);

// Converts an NSError back to a C4Error (used by the WebSocket implementation)
void convertError(NSError* error, C4Error *outError);

BOOL createError(CBLStatus status, NSError* _Nullable * outError);

BOOL createError(CBLStatus status, NSString  * _Nullable  desc, NSError* _Nullable * outError);

NS_ASSUME_NONNULL_END
