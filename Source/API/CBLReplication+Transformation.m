//
//  CBLReplication+Transformation.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 3/14/14.
//
//

#import "CBLReplication+Transformation.h"
#import "CouchbaseLitePrivate.h"


@implementation CBLReplication (Transformation)

- (CBLPropertiesTransformationBlock) propertiesTransformationBlock {
    return _propertiesTransformationBlock;
}

- (void) setPropertiesTransformationBlock:(CBLPropertiesTransformationBlock)block {
    _propertiesTransformationBlock = block;
}

@end
