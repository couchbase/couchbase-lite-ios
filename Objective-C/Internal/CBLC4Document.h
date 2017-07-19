//
//  CBLC4Document.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/11/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLFLDataSource.h"
#import "c4.h"

NS_ASSUME_NONNULL_BEGIN

@interface CBLC4Document : NSObject <CBLFLDataSource>

@property (readonly, nonatomic) C4Document* rawDoc;

@property (readonly, nonatomic) C4DocumentFlags flags;

@property (readonly, nonatomic) C4SequenceNumber sequence;

@property (readonly, nonatomic) C4String revID;

@property (readonly, nonatomic) C4Revision selectedRev;

+ (instancetype) document: (C4Document*)document;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

- (instancetype) initWithRawDoc: (C4Document*)rawDoc;

@end

NS_ASSUME_NONNULL_END
