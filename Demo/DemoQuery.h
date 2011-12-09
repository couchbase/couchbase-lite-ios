//
//  DemoQuery.h
//  CouchCocoa
//
//  Created by Jens Alfke on 6/1/11.
//  Copyright (c) 2011 Couchbase, Inc, Inc.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import <Cocoa/Cocoa.h>
@class CouchQuery, CouchLiveQuery, RESTOperation;


/** Simple controller for CouchDB demo apps.
    This class acts as glue between a CouchQuery (a CouchDB view) and an NSArrayController.
    The app can then bind its UI controls to the NSArrayController and get basic CRUD operations
    without needing any code. */
@interface DemoQuery : NSObject
{
    CouchLiveQuery* _query;
    RESTOperation* _op;
    NSMutableArray* _entries;
    Class _modelClass;
}

- (id) initWithQuery: (CouchQuery*)query;

/** Class to instantiate for entries. Defaults to DemoItem. */
@property (assign) Class modelClass;

/** The documents returned by the query, wrapped in DemoItem objects.
    An NSArrayController can be bound to this property. */
//@property (readonly) NSMutableArray* entries;

@end
