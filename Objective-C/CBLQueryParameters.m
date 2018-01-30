//
//  CBLQueryParameters.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 7/7/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLQueryParameters.h"
#import "CBLQuery+Internal.h"


@interface CBLQueryParameters()
@property (readonly, nonatomic, nullable) NSDictionary* data;
@end

@implementation CBLQueryParameters {
    BOOL _readonly;
    NSMutableDictionary* _data;
}

- (instancetype) init {
    return [self initWithParameters: nil readonly: NO];
}


- (instancetype) initWithParameters: (nullable CBLQueryParameters*)parameters {
   return [self initWithParameters: parameters readonly: NO];
}


- (instancetype) initWithParameters: (nullable CBLQueryParameters*)parameters
                           readonly: (BOOL)readonly {
    self = [super init];
    if (self) {
        if (parameters.data)
            _data = [NSMutableDictionary dictionaryWithDictionary: parameters.data];
        _readonly = readonly;
    }
    return self;
}


- (void) setValue: (id)value forName: (NSString*)name {
    [self checkReadonly];
    
    if (!_data)
        _data = [NSMutableDictionary dictionary];
    
    if (!value)
        value = [NSNull null]; // Only for Apple platform
    
    _data[name] = value;
}


- (void) setString: (nullable NSString*)value forName: (NSString*)name {
    [self setValue: value forName: name];
}


- (void) setNumber: (nullable NSNumber*)value forName: (NSString*)name {
    [self setValue: value forName: name];
}


- (void) setInteger: (NSInteger)value forName: (NSString*)name {
    [self setValue: @(value) forName: name];
}


- (void) setLongLong: (long long)value forName: (NSString*)name {
    [self setValue: @(value) forName: name];
}


- (void) setFloat: (float)value forName: (NSString*)name {
    [self setValue: @(value) forName: name];
}


- (void) setDouble: (double)value forName: (NSString*)name {
    [self setValue: @(value) forName: name];
}


- (void) setBoolean: (BOOL)value forName: (NSString*)name {
    [self setValue: @(value) forName: name];
}


- (void) setDate: (nullable NSDate*)value forName: (NSString*)name {
    [self setValue: value forName: name];
}


- (nullable id) valueForName:(NSString *)name {
    return [_data objectForKey: name];
}


#pragma mark - Internal


- (NSDictionary*) data {
    return _data;
}


- (void) checkReadonly {
    if (_readonly) {
        [NSException raise: NSInternalInconsistencyException
                    format: @"This parameters object is readonly."];
    }
}


- (nullable NSData*) encodeAsJSON: (NSError**)outError {
    if (_data)
        return [NSJSONSerialization dataWithJSONObject: _data options: 0 error: outError];
    else
        return nil;
}

@end
