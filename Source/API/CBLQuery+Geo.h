//
//  CBLQuery+Geo.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 9/23/13.
//  Copyright (c) 2013 Couchbase, Inc. All rights reserved.
//

#import "CBLQuery.h"
#import "CBLGeometry.h"

#if __has_feature(nullability) // Xcode 6.3+
#pragma clang assume_nonnull begin
#else
#define nullable
#define __nullable
#endif


/** CBLQuery interface for geo-queries.
    To use this, the view's map function must have emitted geometries (points, rects, etc.)
    as keys using the functions CBLGeoPointKey(), CBLGeoRectKey(), or CBLGeoJSONKey(). */
@interface CBLQuery (Geo)

/** The geometric bounding box to search. Setting this property causes the query to
    search geometries rather than keys. */
@property CBLGeoRect boundingBox;

@end


/** A result row from a CouchbaseLite geo-query.
    A CBLQuery with its .boundingBox property set will produce CBLGeoQueryRows. */
@interface CBLGeoQueryRow : CBLQueryRow

/** The row's geo bounding box in native form.
    If the emitted geo object was a point, the boundingBox's min and max will be equal.
    Note: The coordinates may have slight round-off error, because SQLite internally stores bounding
    boxes as 32-bit floats, but the coordinates are always rounded outwards -- making the bounding
    box slightly larger -- to avoid false negatives in searches. */
@property (readonly, nonatomic) CBLGeoRect boundingBox;

/** The GeoJSON object emitted as the key of the emit() call by the map function.
    The format is a parsed GeoJSON point or polygon; see http://geojson.org/geojson-spec */
@property (readonly, nullable) NSDictionary* geometry;

/** The GeoJSON object type of the row's geometry.
    Usually @"Point" or @"Rectangle", but may be another type if the emitted key was GeoJSON.
    (The "Rectangle" type is not standard GeoJSON.) */
@property (readonly, nonatomic, nullable) NSString* geometryType;

@end


#if __has_feature(nullability)
#pragma clang assume_nonnull end
#endif
