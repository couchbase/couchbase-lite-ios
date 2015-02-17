//
//  CBLSpecialKey.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 4/15/14.
//  Copyright (c) 2014-2015 Couchbase, Inc. All rights reserved.
//

#import "CBLGeometry.h"


// Special key type returned by CBLTextKey(), CBLGeoPointKey(), etc.
@interface CBLSpecialKey : NSObject

- (instancetype) initWithText: (NSString*)text;
@property (readonly, nonatomic) NSString* text;

- (instancetype) initWithPoint: (CBLGeoPoint)point;
- (instancetype) initWithRect: (CBLGeoRect)rect;
- (instancetype) initWithGeoJSON: (NSDictionary*)geoJSON;
@property (readonly, nonatomic) CBLGeoRect rect;
@property (readonly, nonatomic) NSData* geoJSONData;

@end
