//
//  TDJSON.m
//  TouchDB
//
//  Created by Jens Alfke on 2/27/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "TDJSON.h"


#if ! USE_NSJSON

#import "JSONKit.h"


@implementation TDJSON


+ (NSData *)dataWithJSONObject:(id)obj
                       options:(TDJSONWritingOptions)opt
                         error:(NSError **)error
{
    Assert(obj);
    return [obj JSONDataWithOptions: 0 error: error];
}


+ (id)JSONObjectWithData:(NSData *)data
                 options:(TDJSONReadingOptions)opt
                   error:(NSError **)error
{
    Assert(data);
    if (opt & (TDJSONReadingMutableContainers | TDJSONReadingMutableLeaves))
        return [data mutableObjectFromJSONDataWithParseOptions: 0 error: error];
    else
        return [data objectFromJSONDataWithParseOptions: 0 error: error];
}


@end


#endif // ! USE_NSJSON
