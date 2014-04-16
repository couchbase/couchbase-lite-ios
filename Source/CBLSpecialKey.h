//
//  CBLSpecialKey.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 4/15/14.
//
//

#import "CBLGeometry.h"


// Special key object returned by CBLMapKey.
@interface CBLSpecialKey : NSObject

- (instancetype) initWithText: (NSString*)text;
@property (readonly, nonatomic) NSString* text;
- (instancetype) initWithPoint: (CBLGeoPoint)point;
- (instancetype) initWithRect: (CBLGeoRect)rect;
- (instancetype) initWithGeoJSON: (NSDictionary*)geoJSON;
@property (readonly, nonatomic) CBLGeoRect rect;
@property (readonly, nonatomic) NSData* geoJSONData;

@end
