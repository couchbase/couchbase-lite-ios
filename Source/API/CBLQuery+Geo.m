//
//  CBLQuery+Geo.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 9/23/13.
//
//

#import "CBLQuery+Geo.h"
#import "CouchbaseLitePrivate.h"


@implementation CBLQuery (Geo)

- (CBLGeoRect) boundingBox {
    return _boundingBox;
}

- (void) setBoundingBox:(CBLGeoRect)boundingBox {
    _boundingBox = boundingBox;
    _isGeoQuery = YES;
}


@end




@implementation CBLGeoQueryRow
{
    CBLGeoRect _boundingBox;
    NSData* _geoJSONData; // nil data means this is a point; empty data means it's a rect.
}


- (instancetype) initWithDocID: (NSString*)docID
                      sequence: (SequenceNumber)sequence
                   boundingBox: (CBLGeoRect)bbox
                   geoJSONData: (NSData*)geoJSONData
                         value: (NSData*)valueData
                 docProperties: (NSDictionary*)docProperties
{
    self = [super initWithDocID: docID
                       sequence: sequence
                            key: nil
                          value: valueData
                  docProperties: docProperties];
    if (self) {
        _boundingBox = bbox;
        _geoJSONData = geoJSONData;
    }
    return self;
}


- (BOOL) isEqual:(id)object {
    if (![super isEqual: object] || ![object isKindOfClass: [CBLGeoQueryRow class]])
        return NO;
    CBLGeoQueryRow* otherRow = object;
    return CBLGeoRectEqual(_boundingBox, otherRow->_boundingBox)
        && $equal(_geoJSONData, otherRow->_geoJSONData);
}


@synthesize boundingBox=_boundingBox;


- (NSDictionary*) geometry {
    if (!_geoJSONData)
        return CBLGeoPointToJSON(_boundingBox.min);
    else if (_geoJSONData.length == 0)
        return CBLGeoRectToJSON(_boundingBox);
    else
        return [CBLJSON JSONObjectWithData: _geoJSONData options: 0 error: NULL];
}


- (NSString*) geometryType {
    if (_geoJSONData == nil )
        return @"Point";
    if (_geoJSONData.length == 0)
        return @"Rectangle";        // this is nonstandard...
    else
        return (self.geometry)[@"type"];
}


// This is used by the router
- (NSDictionary*) asJSONDictionary {
    NSMutableDictionary* dict = [[super asJSONDictionary] mutableCopy];
    if (!dict[@"error"]) {
        [dict removeObjectForKey: @"key"];
        dict[@"geometry"] = self.geometry;
    }
    return dict;
}


@end