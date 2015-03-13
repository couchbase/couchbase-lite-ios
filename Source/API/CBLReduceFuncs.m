//
//  CBLReduceFuncs.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/15/14.
//  Copyright (c) 2014-2015 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#include "CBLReduceFuncs.h"
#include "CBLView.h"


static NSMutableDictionary* sReduceFuncs;


// Quickselect impl copied from <http://www.sourcetricks.com/2011/06/quick-select.html>

static size_t partition(double input[], size_t p, size_t r) {
    double pivot = input[r];
    while ( p < r ) {
        while ( input[p] < pivot )
            p++;
        while ( input[r] > pivot )
            r--;
        if ( input[p] == input[r] )
            p++;
        else if ( p < r ) {
            double tmp = input[p];
            input[p] = input[r];
            input[r] = tmp;
        }
    }
    return r;
}

// Returns the k'th smallest element of input[p...r] (inclusive)
static double quick_select(double input[], size_t p, size_t r, size_t k) {
    if ( p == r )
        return input[p];
    size_t j = partition(input, p, r);
    size_t length = j - p + 1;
    if ( length == k )
        return input[j];
    else if ( k < length )
        return quick_select(input, p, j - 1, k);
    else
        return quick_select(input, j + 1, r, k - length);
}

static double median(double input[], size_t length) {
    if (length == 0)
        return 0.0;
    double m = quick_select(input, 0, length-1, length/2);
    if (length % 2 == 0)
        m = (m + quick_select(input, 0, length-1, length/2 + 1)) / 2.0;
    return m;
}


static double stddev(double input[], size_t length) {
    // Via <https://en.wikipedia.org/wiki/Standard_deviation#Rapid_calculation_methods>
    double a = 0.0, q = 0.0;
    for (NSUInteger k = 1; k <= length; k++) {
        double x = input[k-1];
        double aOld = a;
        a += (x - a) / k;
        q += (x - aOld) * (x - a);
    }
    return sqrt(q / (length - 1));
}


static NSNumber* withDoubles(NSArray* values, double (*fn)(double[], size_t)) {
    NSUInteger n = values.count;
    double* input = malloc(n * sizeof(double));
    for (NSUInteger i = 0; i < n; i++)
        input[i] = [values[i] doubleValue];
    double m = fn(input, n);
    free(input);
    return @(m);
}


// https://wiki.apache.org/couchdb/Built-In_Reduce_Functions#A_stats
static NSDictionary* stats(NSArray* values) {
    double sum=0, sumsqr=0, min=INFINITY, max=-INFINITY;
    for (id value in values) {
        double n = $castIf(NSNumber, value).doubleValue;
        sum += n;
        sumsqr += n*n;
        min = MIN(min, n);
        max = MAX(max, n);
    }
    return @{@"count": @(values.count),
             @"sum": @(sum), @"sumsqr": @(sumsqr),
             @"min": @(min), @"max": @(max)};
}


static void initializeReduceFuncs(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        //NOTE: None of these support rereduce! They'll need to be reimplemented when we add
        // rereduce support to CBLView.
        sReduceFuncs = [NSMutableDictionary dictionary];
        sReduceFuncs[@"count"] =    REDUCEBLOCK(return @(values.count););
        sReduceFuncs[@"sum"] =      REDUCEBLOCK(return [values valueForKeyPath: @"@sum.self"];);
        sReduceFuncs[@"min"] =      REDUCEBLOCK(return [values valueForKeyPath: @"@min.self"];);
        sReduceFuncs[@"max"] =      REDUCEBLOCK(return [values valueForKeyPath: @"@max.self"];);
        sReduceFuncs[@"average"] =  REDUCEBLOCK(return [values valueForKeyPath: @"@avg.self"];);
        sReduceFuncs[@"median"] =   REDUCEBLOCK(return withDoubles(values, median););
        sReduceFuncs[@"stddev"] =   REDUCEBLOCK(return withDoubles(values, stddev););
        sReduceFuncs[@"stats"] =    REDUCEBLOCK(return stats(values););
    });
}


void CBLRegisterReduceFunc(NSString* name, CBLReduceBlock block) {
    initializeReduceFuncs();
    @synchronized(sReduceFuncs) {
        sReduceFuncs[name] = block;
    }
}


CBLReduceBlock CBLGetReduceFunc(NSString* name) {
    initializeReduceFuncs();
    @synchronized(sReduceFuncs) {
        return sReduceFuncs[name];
    }
}
