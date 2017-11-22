//
//  CBLListenerToken.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 11/20/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

/**
 Listener token returned when adding a change listener. The token is used
 for removing the added change listener.
 */
@protocol CBLListenerToken <NSObject>

@end

NS_ASSUME_NONNULL_END
