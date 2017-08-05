//
//  CBLAuthenticator.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 6/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>

/** 
 Authenticator objects provide server authentication credentials to the replicator.
 CBLAuthenticator is an abstract superclass; you must instantiate one of its subclasses.
 CBLAuthenticator is not meant to be subclassed by applications.
 */
@interface CBLAuthenticator : NSObject
@end
