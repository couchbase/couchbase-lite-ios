//
//  CBLQueryParameters.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 7/7/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLQueryParameters.h"
#import "CBLQuery+Internal.h"

@interface CBLQueryParametersBuilder()

@property (readonly, nonatomic, nullable) NSDictionary* data;

- (instancetype) initWithParameters: (nullable CBLQueryParameters*)parameters;

@end

@interface CBLQueryParameters()

@property (readonly, nonatomic, nullable) NSDictionary* data;

@end

@implementation CBLQueryParametersBuilder {
    NSMutableDictionary* _data;
}

- (instancetype) initWithParameters: (nullable CBLQueryParameters*)parameters
{
    self = [super init];
    if (self) {
        if (parameters.data)
            _data = [NSMutableDictionary dictionaryWithDictionary: parameters.data];
    }
    return self;
}


- (NSDictionary*) data {
    return _data;
}


- (void) setValue: (id)value forName: (NSString*)name {
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

@end


@implementation CBLQueryParameters

@synthesize data=_data;

- (instancetype) initWithBlock: (nullable void(^)(CBLQueryParametersBuilder* builder))block
{
    return [self initWithParameters: nil block: block];
}


- (instancetype) initWithParameters: (nullable CBLQueryParameters*)parameters
                              block: (nullable void(^)(CBLQueryParametersBuilder* builder))block
{
    self = [super init];
    if (self) {
        CBLQueryParametersBuilder* builder =
        [[CBLQueryParametersBuilder alloc] initWithParameters: parameters];
        
        if (block)
            block(builder);
        
        if (builder.data)
            _data = [NSDictionary dictionaryWithDictionary: builder.data];
    }
    return self;
}


- (nullable id) valueForName:(NSString *)name {
    return [_data objectForKey: name];
}


#pragma mark - Internal


- (nullable NSData*) encodeAsJSON: (NSError**)outError {
    if (_data)
        return [NSJSONSerialization dataWithJSONObject: _data options: 0 error: outError];
    else
        return nil;
}


@end
