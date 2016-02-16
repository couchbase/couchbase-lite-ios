//
//  CBLQueryRow+Router.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/15/16.
//  Copyright © 2016 Couchbase, Inc. All rights reserved.
//

#import "CBLQueryRow+Router.h"
#import "CBLQuery+FullTextSearch.h"
#import "CBLQuery+Geo.h"
#import "CBLInternal.h"


@implementation CBLQueryRow (Router)

- (NSDictionary*) asJSONDictionary {
    id value = self.value;
    if (value || self.sourceDocumentID) {
        return $dict({@"key", self.key},
                     {@"value", self.value},
                     {@"id", self.sourceDocumentID},
                     {@"doc", self.documentProperties});
    } else {
        return $dict({@"key", self.key}, {@"error", @"not_found"});
    }
}

@end



@implementation CBLFullTextQueryRow (Router)

// Overridden to add FTS result info
- (NSDictionary*) asJSONDictionary {
    NSMutableDictionary* dict = [[super asJSONDictionary] mutableCopy];
    if (!dict[@"error"]) {
        [dict removeObjectForKey: @"key"];
        if (self.snippet)
            dict[@"snippet"] = [self snippetWithWordStart: @"[" wordEnd: @"]"];
        NSUInteger matchCount = self.matchCount;
        if (matchCount > 0) {
            NSMutableArray* matches = [[NSMutableArray alloc] init];
            for (NSUInteger i = 0; i < matchCount; ++i) {
                NSRange r = [self textRangeOfMatch: i];
                [matches addObject: @{@"term": @([self termIndexOfMatch: i]),
                                      @"range": @[@(r.location), @(r.length)]}];
            }
            dict[@"matches"] = matches;
        }
    }
    return dict;
}

@end



@implementation CBLGeoQueryRow (Router)

// Override to return same format as GeoCouch <https://github.com/couchbase/geocouch/>
- (NSDictionary*) asJSONDictionary {
    NSMutableDictionary* dict = [[super asJSONDictionary] mutableCopy];
    if (!dict[@"error"]) {
        [dict removeObjectForKey: @"key"];
        dict[@"geometry"] = self.geometry;
        CBLGeoRect bbox = self.boundingBox;
        dict[@"bbox"] = @[@(bbox.min.x), @(bbox.min.y),
                          @(bbox.max.x), @(bbox.max.y)];
    }
    return dict;
}

@end
