//
//  CBLKVOProxy.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 8/18/15.
//  Copyright © 2015 Couchbase, Inc. All rights reserved.
//

#import "CBLKVOProxy.h"


@implementation CBLKVOProxy
{
    id _object;
    NSString* _keyPath;
    id _value;
}


- (CBLKVOProxy*) initWithObject: (id)object
                        keyPath: (NSString*)keyPath
{
    self = [super init];
    if (self) {
        _object = object;
        _keyPath = keyPath;

        [_object addObserver: self forKeyPath: keyPath options: NSKeyValueObservingOptionNew
                     context: NULL];
        _value = [_object valueForKeyPath: keyPath];
    }
    return self;
}


- (void)dealloc {
    [_object removeObserver: self forKeyPath: _keyPath];
}


- (void) removeObserver: (NSObject*)observer forKeyPath: (NSString*)keyPath {
    [super removeObserver: observer forKeyPath: keyPath];
    [_object removeObserver: self forKeyPath: keyPath];
    _object = nil;
}


- (id) valueForKeyPath:(NSString *)keyPath {
    if ([keyPath isEqualToString: _keyPath])
        return _value;
    else
        return [super valueForKeyPath: keyPath];
}


- (void) valueChanged: (NSDictionary*)change {
    [self willChangeValueForKey: _keyPath];
    _value = change[NSKeyValueChangeNewKey];
    [self didChangeValueForKey: _keyPath];
}


- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context
{
    if (object == _object) {
        [self performSelectorOnMainThread: @selector(valueChanged:)
                               withObject: change
                            waitUntilDone: NO];
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}


@end
