//
//  TDDocRevision.m
//  TouchDB
//
//  Created by Jens Alfke on 6/17/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "TDDocRevision.h"
#import "TDDatabase+Insertion.h"
#import "TDRevision.h"
#import "TDDocument.h"
#import "TDStatus.h"


@implementation TDDocRevision


- (id)initWithDocument: (TDDocument*)doc revision: (TDRevision*)rev {
    self = [super init];
    if (self) {
        _document = [doc retain];
        _rev = [rev retain];
    }
    return self;
}

- (void)dealloc {
    [_document release];
    [_rev release];
    [super dealloc];
}


@synthesize document=_document, rev=_rev;

- (TDDatabase*) database    {return _document.database;}
- (NSString*) revisionID    {return _rev.revID;}

- (BOOL) isDeleted          {return [self.properties objectForKey: @"_deleted"] != nil;}


- (NSDictionary*) properties {
    NSDictionary* properties = _rev.properties;
    if (!properties) {
        TDStatus status = [self.database loadRevisionBody: _rev options: 0];
        if (TDStatusIsError(status))
            Warn(@"Couldn't load properties of %@: %d", self, status);
        properties = _rev.properties;
    }
    return properties;
}

- (NSDictionary*) userProperties {
    NSDictionary* rep = self.properties;
    if (!rep)
        return nil;
    NSMutableDictionary* props = [NSMutableDictionary dictionary];
    for (NSString* key in rep) {
        if (![key hasPrefix: @"_"])
            [props setObject: [rep objectForKey: key] forKey: key];
    }
    return props;
}

- (id) propertyForKey: (NSString*)key {
    return [self.properties objectForKey: key];
}

- (BOOL) propertiesAreLoaded {
    return _rev.properties != nil;
}


#pragma mark - SAVING:


- (TDDocRevision*) putProperties: (NSDictionary*)properties error: (NSError**)outError {
    return [_document putProperties: properties
                          prevRevID: _rev.revID
                              error: outError];
}


- (TDDocRevision*) deleteDocument: (NSError**)outError {
    return [self putProperties: nil error: outError];
}


@end
