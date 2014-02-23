//
//  CBLModel_Internal.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/12/13.
//  Copyright (c) 2013 Couchbase, Inc. All rights reserved.
//

#import "CBLModel.h"

@interface CBLModel ()
{
    CBLDocument* _document;
    CFAbsoluteTime _changedTime;
    bool _autosaves :1;
    bool _isNew     :1;
    bool _needsSave :1;
    bool _saving    :1;

    NSMutableDictionary *_properties;
    NSMutableSet* _changedNames;        // Names of properties that have been changed but not saved
    NSMutableDictionary* _changedAttachments;
}
@property (readwrite, retain) CBLDocument* document;
@property (readwrite) bool needsSave;

/** Cached property values, including changed values */
@property (readonly, nonatomic) NSMutableDictionary *properties;

/** Copy of the currently cached property values, including changed values */
@property (readonly) NSDictionary *currentProperties;

- (void) cacheValue: (id)value ofProperty: (NSString*)property changed: (BOOL)changed;
- (void) willSave: (NSSet*)changedProperties;   // overridable
- (CBLModel*) modelWithDocID: (NSString*)docID
                 forProperty: (NSString*)property
                     ofClass: (Class)declaredClass;
- (void) markPropertyNeedsSave: (NSString*)property;
@end
