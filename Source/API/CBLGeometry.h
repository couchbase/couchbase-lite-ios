//
//  CBLGeometry.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 9/22/13.
//  Copyright (c) 2013 Couchbase, Inc. All rights reserved.
//

#import "CBLBase.h"

NS_ASSUME_NONNULL_BEGIN

/** A 2D geometric point. */
typedef struct CBLGeoPoint {
    double x, y;
} CBLGeoPoint;

/** A 2D geometric rectangle.
    Note that unlike CGRect and NSRect, this stores max coords, not size.
    A rectangle with max coords equal to the min is equivalent to a point.
    It is illegal for the max coords to be less than the min. */
typedef struct CBLGeoRect {
    CBLGeoPoint min, max;
} CBLGeoRect;


#ifdef __cplusplus
extern "C" {
#endif


/** Compares two rectangles for equality. */
static inline BOOL CBLGeoRectEqual(CBLGeoRect a, CBLGeoRect b) {
    return a.min.x == b.min.x && a.min.y == b.min.y && a.max.x == b.max.x && a.max.y == b.max.y;
}

/** Returns YES if a rectangle is empty, i.e. equivalent to a single point. */
static inline BOOL CBLGeoRectIsEmpty(CBLGeoRect r) {
    return r.min.x == r.max.x && r.min.y == r.max.y;
}


/** Converts a string of four comma-separated numbers ("x0,y0,x1,y1") to a rectangle. */
BOOL CBLGeoCoordsStringToRect(NSString* __nullable coordsStr, CBLGeoRect* outRect);


#pragma mark - CONVERTING TO/FROM JSON:

/** Converts a point to GeoJSON format.
    For details see http://geojson.org/geojson-spec.html#point */
CBLJSONDict* CBLGeoPointToJSON(CBLGeoPoint pt);

/** Converts a rectangle to GeoJSON format (as a polygon.)
    For details see http://geojson.org/geojson-spec.html#polygon */
CBLJSONDict* CBLGeoRectToJSON(CBLGeoRect rect);

/** Computes the bounding box of a GeoJSON object.
    Currently only implemented for points and polygons. */
BOOL CBLGeoJSONBoundingBox(NSDictionary* __nullable geoJSON, CBLGeoRect* outBBox);


/** Converts a point to a JSON-compatible array of two coordinates. */
CBLArrayOf(NSNumber*)* CBLGeoPointToCoordPair(CBLGeoPoint pt);

/** Converts a JSON array of two coordinates [x,y] back into a point. */
BOOL CBLGeoCoordPairToPoint(NSArray* __nullable coords, CBLGeoPoint* outPoint);

/** Converts a JSON array of four coordinates [x0, y0, x1, y1] to a rectangle. */
BOOL CBLGeoCoordsToRect(NSArray* __nullable coords, CBLGeoRect* outRect);

#pragma mark - KEYS FOR MAP FUNCTIONS:

/** Returns a special value that, when emitted as a key, is indexed as a geometric point.
    Used inside a map block, like so: `emit(CBLPointKey(3.0, 4.0), value);` */
id CBLGeoPointKey(double x, double y);

/** Returns a special value that, when emitted as a key, is indexed as a geometric rectangle. */
id CBLGeoRectKey(double x0, double y0, double x1, double y1);

/** Returns a special value that, when emitted as a key, is indexed as a GeoJSON
    shape. Currently only its bounding box is stored. 
    Only points and polygons are supported; other shapes return nil. */
id CBLGeoJSONKey(NSDictionary* geoJSON);


#ifdef __cplusplus
}
#endif


NS_ASSUME_NONNULL_END
