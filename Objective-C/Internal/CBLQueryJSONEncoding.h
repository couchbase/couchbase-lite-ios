//
//  CBLQueryJSONEncoding.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 11/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

@protocol CBLQueryJSONEncoding <NSObject>

/** Encode as a JSON object. */
- (id) asJSON;

@end
