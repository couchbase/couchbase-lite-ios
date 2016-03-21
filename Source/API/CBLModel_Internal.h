//
//  CBLModel_Internal.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/12/13.
//  Copyright (c) 2013 Couchbase, Inc. All rights reserved.
//

#import "CBLModel.h"

NS_ASSUME_NONNULL_BEGIN

UsingLogDomain(Model);

@interface CBLModel ()
{
    CBLDocument* _document;
    CFAbsoluteTime _changedTime;
    bool _autosaves :1;
    bool _isNew     :1;
    bool _needsSave :1;
    bool _saving    :1;

    NSMutableDictionary* _properties;   // Cached property values, including changed values
    NSMutableSet* _changedNames;        // Names of properties that have been changed but not saved
    NSMutableDictionary* _changedAttachments;
}
@property (readwrite, strong, nullable) CBLDocument* document;
@property (readwrite) bool needsSave;
@property (readonly) NSDictionary* currentProperties;

- (instancetype) initWithDocument: (nullable CBLDocument*)document
                       orDatabase: (nullable CBLDatabase*)database NS_DESIGNATED_INITIALIZER;

- (nullable id) getValueOfProperty: (NSString*)property ofClass: (Class)klass;
- (void) cacheValue: (id)value ofProperty: (NSString*)property changed: (BOOL)changed;
- (void) willSave: (NSSet*)changedProperties;   // overridable
- (nullable CBLModel*) modelWithDocID: (NSString*)docID
                          forProperty: (NSString*)property
                              ofClass: (nullable Class)declaredClass;
- (void) markPropertyNeedsSave: (NSString*)property;
@end


NS_ASSUME_NONNULL_END
