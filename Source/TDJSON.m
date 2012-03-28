//
//  TDJSON.m
//  TouchDB
//
//  Created by Jens Alfke on 2/27/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "TDJSON.h"

#if !USE_NSJSON
#import "JSONKit.h"
#endif


@implementation TDJSON


#if USE_NSJSON


+ (NSData *)dataWithJSONObject:(id)object
                       options:(TDJSONWritingOptions)options
                         error:(NSError **)error
{
    if ((options & TDJSONWritingAllowFragments)
            && ![object isKindOfClass: [NSDictionary class]]
            && ![object isKindOfClass: [NSArray class]]) {
        // NSJSONSerialization won't write fragments, so if I get one wrap it in an array first:
        object = [[NSArray alloc] initWithObjects: &object count: 1];
        NSData* json = [super dataWithJSONObject: object 
                                         options: (options & ~TDJSONWritingAllowFragments)
                                           error: nil];
        [object release];
        return [json subdataWithRange: NSMakeRange(1, json.length - 2)];
    } else {
        return [super dataWithJSONObject: object options: options error: error];
    }
}


#else // not USE_NSJSON

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


#endif // USE_NSJSON


+ (NSString*) stringWithJSONObject:(id)obj
                           options:(TDJSONWritingOptions)opt
                             error:(NSError **)error
{
    return [[self dataWithJSONObject: obj options: opt error: error] my_UTF8ToString];
}


@end
