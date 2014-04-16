//
//  CBLSpecialKey.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 4/15/14.
//
//

#import "CBLSpecialKey.h"
#import "CBLView.h"


@implementation CBLSpecialKey
{
    NSString* _text;
    CBLGeoRect _rect;
    NSData* _geoJSONData;
}

- (instancetype) initWithText: (NSString*)text {
    Assert(text != nil);
    self = [super init];
    if (self) {
        _text = text;
    }
    return self;
}

- (instancetype) initWithPoint: (CBLGeoPoint)point {
    self = [super init];
    if (self) {
        _rect = (CBLGeoRect){point, point};
        _geoJSONData = [CBLJSON dataWithJSONObject: CBLGeoPointToJSON(point) options: 0 error:NULL];
        _geoJSONData = [NSData data]; // Empty _geoJSONData means the bbox is a point
    }
    return self;
}

- (instancetype) initWithRect: (CBLGeoRect)rect {
    self = [super init];
    if (self) {
        _rect = rect;
        // Don't set _geoJSONData; if nil it defaults to the same as the bbox.
    }
    return self;
}

- (instancetype) initWithGeoJSON: (NSDictionary*)geoJSON {
    self = [super init];
    if (self) {
        if (!CBLGeoJSONBoundingBox(geoJSON, &_rect))
            return nil;
        _geoJSONData = [CBLJSON dataWithJSONObject: geoJSON options: 0 error: NULL];
    }
    return self;
}

@synthesize text=_text, rect=_rect, geoJSONData=_geoJSONData;

- (NSString*) description {
    if (_text) {
        return $sprintf(@"CBLTextKey(\"%@\")", _text);
    } else if (_rect.min.x==_rect.max.x && _rect.min.y==_rect.max.y) {
        return $sprintf(@"CBLGeoPointKey(%g, %g)", _rect.min.x, _rect.min.y);
    } else {
        return $sprintf(@"CBLGeoRectKey({%g, %g}, {%g, %g})",
                        _rect.min.x, _rect.min.y, _rect.max.x, _rect.max.y);
    }
}

@end




id CBLTextKey(NSString* text) {
    return [[CBLSpecialKey alloc] initWithText: text];
}

id CBLGeoPointKey(double x, double y) {
    return [[CBLSpecialKey alloc] initWithPoint: (CBLGeoPoint){x,y}];
}

id CBLGeoRectKey(double x0, double y0, double x1, double y1) {
    return [[CBLSpecialKey alloc] initWithRect: (CBLGeoRect){{x0,y0},{x1,y1}}];
}

id CBLGeoJSONKey(NSDictionary* geoJSON) {
    id key = [[CBLSpecialKey alloc] initWithGeoJSON: geoJSON];
    if (!key)
        Warn(@"CBLGeoJSONKey doesn't recognize %@",
             [CBLJSON stringWithJSONObject: geoJSON options:0 error: NULL]);
    return key;
}
