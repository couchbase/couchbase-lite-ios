//
//  CBLGeometry.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 9/22/13.
//
//

#import "CBLGeometry.h"


NSArray* CBLGeoPointToCoordPair(CBLGeoPoint pt) {
    return @[@(pt.x), @(pt.y)];
}

NSDictionary* CBLGeoPointToJSON(CBLGeoPoint pt) {
    return $dict({@"type", @"Point"}, {@"coordinates", CBLGeoPointToCoordPair(pt)});
}

NSDictionary* CBLGeoRectToJSON(CBLGeoRect rect) {
    id lowerLeft = CBLGeoPointToCoordPair(rect.min);
    if (CBLGeoRectIsEmpty(rect))
        return  @{@"type": @"Point", @"coordinates": lowerLeft};
    id upperLeft  = CBLGeoPointToCoordPair((CBLGeoPoint){rect.min.x, rect.max.y});
    id upperRight = CBLGeoPointToCoordPair(rect.max);
    id lowerRight = CBLGeoPointToCoordPair((CBLGeoPoint){rect.max.x, rect.min.y});
    NSArray* ring = @[lowerLeft, upperLeft, upperRight, lowerRight, lowerLeft];
    return  @{@"type": @"Polygon", @"coordinates": @[ring]};
}


BOOL CBLGeoCoordPairToPoint(NSArray* coords, CBLGeoPoint* outPoint) {
    if (![coords isKindOfClass: [NSArray class]] || coords.count != 2)
        return NO;
    NSNumber* x = $castIf(NSNumber, coords[0]);
    NSNumber* y = $castIf(NSNumber, coords[1]);
    if (!x || !y)
        return NO;
    outPoint->x = x.doubleValue;
    outPoint->y = y.doubleValue;
    return YES;
}


BOOL CBLGeoJSONBoundingBox(NSDictionary* geoJSON, CBLGeoRect* outRect) {
    // http://geojson.org/geojson-spec.html
    NSArray* coordinates = $castIf(NSArray, geoJSON[@"coordinates"]);
    if (!coordinates)
        return NO;
    NSString* type = $castIf(NSString, geoJSON[@"type"]);
    if ([type isEqualToString: @"Point"]) {
        // coordinates of a point are just [x, y]
        if (!CBLGeoCoordPairToPoint(coordinates, &outRect->min))
            return NO;
        outRect->max = outRect->min;
    } else if ([type isEqualToString: @"Polygon"]) {
        // coordinates of a polygon are an array of arrays of [x, y]
        BOOL first = YES;
        for (id ring in coordinates) {
            if (![ring isKindOfClass: [NSArray class]])
                return NO;
            for (id coords in ring) {
                CBLGeoPoint pt;
                if (!CBLGeoCoordPairToPoint(coords, &pt))
                    return NO;
                if (first) {
                    outRect->min = outRect->max = pt;
                    first = NO;
                } else {
                    outRect->min.x = MIN(outRect->min.x, pt.x);
                    outRect->min.y = MIN(outRect->min.y, pt.y);
                    outRect->max.x = MAX(outRect->max.x, pt.x);
                    outRect->max.y = MAX(outRect->max.y, pt.y);
                }
            }
        }
    } else {
        return NO;
    }
    return YES;
}




TestCase(CBLGeometry) {
    // Convert a rect to GeoJSON and back:
    CBLGeoRect rect = {{-115,-10}, {-90, 12}};
    NSDictionary* json = @{@"type": @"Polygon",
                           @"coordinates": @[ @[
                                   @[@-115,@-10], @[@-115, @12], @[@-90, @12],
                                   @[@-90, @-10], @[@-115, @-10]
                                   ]]};
    AssertEqual(CBLGeoRectToJSON(rect), json);

    CBLGeoRect bbox;
    Assert(CBLGeoJSONBoundingBox(json, &bbox));
    Assert(CBLGeoRectEqual(bbox, rect));
}