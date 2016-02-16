//
//  CBLQuery+Geo.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 9/23/13.
//  Copyright (c) 2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBLQuery+Geo.h"
#import "CBLInternal.h"


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
                   docRevision: (CBL_Revision*)docRevision
{
    self = [super initWithDocID: docID
                       sequence: sequence
                            key: nil
                          value: valueData
                    docRevision: docRevision];
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


@end