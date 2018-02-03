//
//  CBLQueryParameters.m
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
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
