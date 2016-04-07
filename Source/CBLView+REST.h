//
//  CBLView+REST.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 4/7/16.
//  Copyright © 2016 Couchbase, Inc. All rights reserved.
//

#import "CBLView.h"
#import "CBLStatus.h"


@interface CBLView (REST)

- (CBLStatus) compileFromDesignDoc;

/** Compiles a view (using the registered CBLViewCompiler) from the properties found in a CouchDB-style design document. */
- (CBLStatus) compileFromProperties: (NSDictionary*)viewProps
                           language: (NSString*)language;

@end
