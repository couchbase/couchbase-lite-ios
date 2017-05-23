//
//  CBLDocumentChange.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/22/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface CBLDocumentChange : NSObject

/** The ID of the document that changed. */
@property (readonly, nonatomic) NSString* documentID;

@end

@protocol CBLDocumentChangeListener <NSObject>

- (void) documentDidChange: (CBLDocumentChange*)change;

@end
