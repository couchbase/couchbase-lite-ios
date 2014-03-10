//
//  CBLGeometry.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 9/22/13.
//  Copyright (c) 2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

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


BOOL CBLGeoCoordsToRect(NSArray* coords, CBLGeoRect* outRect) {
    if (![coords isKindOfClass: [NSArray class]] || coords.count != 4)
        return NO;
    return CBLGeoCoordPairToPoint([coords subarrayWithRange: NSMakeRange(0,2)], &outRect->min)
        && CBLGeoCoordPairToPoint([coords subarrayWithRange: NSMakeRange(2,2)], &outRect->max);
}


BOOL CBLGeoCoordsStringToRect(NSString* coordsStr, CBLGeoRect* outRect) {
    NSArray* bboxArray = [coordsStr componentsSeparatedByString: @","];
    if (bboxArray.count != 4)
        return NO;
    double coords[4];
    for (NSUInteger i = 0; i < 4; i++)
        coords[i] = [bboxArray[i] doubleValue];
    *outRect = (CBLGeoRect){{coords[0],coords[1]}, {coords[2],coords[3]}};
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

    Assert(CBLGeoCoordsStringToRect(@"-115,-10,-90,12.0",&bbox));
    Assert(CBLGeoRectEqual(bbox, rect));
}
