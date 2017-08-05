//
//  CBLDocumentChange.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/22/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>

/** Document change information  */
@interface CBLDocumentChange : NSObject

/** The ID  of the document that changed. */
@property (readonly, nonatomic) NSString* documentID;

@end


/** A protocol defining a document change listener. */
@protocol CBLDocumentChangeListener <NSObject>

/** A method to be called when the document has been changed. */
- (void) documentDidChange: (CBLDocumentChange*)change;

@end
