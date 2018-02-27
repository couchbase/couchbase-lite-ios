//
//  CBLTimeSeries.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 10/26/15.
//  Copyright © 2015 Couchbase, Inc. All rights reserved.
//

#import "CBLTimeSeries.h"
#import "CouchbaseLitePrivate.h"
#import "CBLDatabase.h"
#import "CBLJSON.h"
#import "CBLDatabase+Internal.h"
#import <stdio.h>
#import <sys/mman.h>


#define kMaxDocSize             (100*1024)  // Max length in bytes of a document
#define kMaxDocEventCount       1000u       // Max number of events to pack into a document


static inline CFAbsoluteTime dateToTime(NSDate* date) {
    return date.timeIntervalSinceReferenceDate;
}

static inline CFAbsoluteTime jsonToTime(id json) {
    return dateToTime([CBLJSON dateWithJSONObject: json]);
}

static inline NSDate* timeToDate(CFAbsoluteTime time) {
    return [NSDate dateWithTimeIntervalSinceReferenceDate: time];
}

static NSString* timeToJSONString(CFAbsoluteTime time) {
    return [CBLJSON JSONObjectWithDate: timeToDate(time)];
}


typedef NSArray<CBLJSONDict*> EventArray;


// Internal enumerator implementation whose -nextObject method just calls a block
@interface CBLTimeSeriesEnumerator : NSEnumerator<CBLJSONDict*>
- (id) initWithBlock: (CBLJSONDict*(^)())block;
@end



@interface CBLTimeSeries ()
@property (readwrite) NSError* lastError;
@end


@implementation CBLTimeSeries
{
    CBLDatabase* _db;
    dispatch_queue_t _queue;
    FILE *_out;
    NSUInteger _eventsInFile;
    NSMutableArray* _docsToAdd;
    BOOL _synchronousFlushing;
}

@synthesize docType=_docType, docIDPrefix=_docIDPrefix, lastError=_lastError;


- (instancetype) initWithDatabase: (CBLDatabase*)db
                          docType: (NSString*)docType
                            error: (NSError**)outError
{
    NSParameterAssert(db);
    NSParameterAssert(docType);
    self = [super init];
    if (self) {
        NSString* filename = [NSString stringWithFormat: @"TS-%@.tslog", docType];
        NSString* path = [db.dir stringByAppendingPathComponent: filename];
        _out = fopen(path.fileSystemRepresentation, "a+"); // append-only, and read
        if (!_out) {
            if (outError)
                *outError = [NSError errorWithDomain: NSPOSIXErrorDomain code: errno userInfo:nil];
            return nil;
        }
        _queue = dispatch_queue_create("CBLTimeSeries", DISPATCH_QUEUE_SERIAL);
        _db = db;
        _docType = [docType copy];
        _docIDPrefix = [NSString stringWithFormat: @"TS-%@-", _docType];
    }
    return self;
}


- (void) dealloc {
    [self stop];
}


- (void) stop {
    if (_queue) {
        dispatch_sync(_queue, ^{
            if (_out) {
                fclose(_out);
                _out = NULL;
            }
        });
        _queue = nil;
    }
    self.lastError = nil;
}


#pragma mark - CAPTURING EVENTS:


- (BOOL) checkError: (int)err {
    if (err == 0)
        return NO;
    Warn(@"CBLTimeSeries: POSIX error %d", err);
    self.lastError = [NSError errorWithDomain: NSPOSIXErrorDomain code: err
                                     userInfo: @{NSLocalizedDescriptionKey: @(strerror(err))}];
    return YES;
}


- (BOOL) checkWriteError {
    return [self checkError: ferror(_out)];
}


- (void) addEvent: (CBLJSONDict*)event {
    [self addEvent: event atTime: CFAbsoluteTimeGetCurrent()];
}


- (void) addEvent: (CBLJSONDict*)event atTime: (CFAbsoluteTime)time {
    Assert(event);
    dispatch_async(_queue, ^{
        NSMutableDictionary* props = [event mutableCopy];
        props[@"t"] = @(time);
        NSData* json = [CBLJSON dataWithJSONObject: props options: 0 error: NULL];
        Assert(json);

        off_t pos = ftell(_out);
        if (pos + json.length + 20 > kMaxDocSize || _eventsInFile >= kMaxDocEventCount) {
            [self transferToDB];
            pos = 0;
        }

        if (fputs(pos==0 ? "[" : ",\n", _out) < 0
                || fwrite(json.bytes, json.length, 1, _out) < 1
                || fflush(_out) < 0)
        {
            [self checkWriteError];
        }
        ++_eventsInFile;
    });
}


- (void) flushAsync: (void(^)(BOOL))onFlushed {
    dispatch_async(_queue, ^{
        BOOL ok = YES;
        if (_eventsInFile > 0 || ftell(_out) > 0) {
            ok = [self transferToDB];
        }
        [_db doAsync: ^{ onFlushed(ok); }];
    });
}


- (BOOL) flush {
    Assert(!_synchronousFlushing);
    _synchronousFlushing = YES;
    __block BOOL transferred = YES;
    dispatch_sync(_queue, ^{
        if (_eventsInFile > 0 || ftell(_out) > 0)
            transferred = [self transferToDB];
    });
    _synchronousFlushing = NO;
    return [self saveQueuedDocs] && transferred;
}


#pragma mark - SAVING EVENTS:


// Must be called on _queue
- (BOOL) transferToDB {
    if (fputs("]", _out) < 0 || fflush(_out) < 0) {
        [self checkWriteError];
        return NO;
    }

    // Parse a JSON array from the (memory-mapped) file:
    size_t length = ftell(_out);
    void* mapped = mmap(NULL, length, PROT_READ, MAP_PRIVATE, fileno(_out), 0);
    if (!mapped)
        return [self checkError: errno];
    NSData* json = [[NSData alloc] initWithBytesNoCopy: mapped length: length freeWhenDone: NO];
    NSError* jsonError;
    EventArray* events = [CBLJSON JSONObjectWithData: json
                                             options: CBLJSONReadingMutableContainers
                                               error: &jsonError];
    munmap(mapped, length);
    if (jsonError) {
        self.lastError = jsonError;
        return NO;
    }

    // Add the events to documents in batches:
    NSUInteger count = events.count;
    for (NSUInteger pos = 0; pos < count; pos += kMaxDocEventCount) {
        NSRange range = {pos, MIN(kMaxDocEventCount, count-pos)};
        EventArray* group = [events subarrayWithRange: range];
        [self addEventsToDB: group];
    }

    // Now erase the file for subsequent events:
    fseek(_out, 0, SEEK_SET);
    ftruncate(fileno(_out), 0);
    _eventsInFile = 0;
    return YES;
}


- (NSString*) docIDForTime: (CFAbsoluteTime)time {
    return [_docIDPrefix stringByAppendingString: timeToJSONString(time)];
}


// Must be called on _queue
- (void) addEventsToDB: (EventArray*)events {
    if (events.count == 0)
        return;
    CFAbsoluteTime time0 = [[events[0] objectForKey: @"t"] doubleValue];
    NSString* time0String = timeToJSONString(time0);
    NSString* docID = [self docIDForTime: time0];
    time0 = jsonToTime(time0String);    // rounded time that the reader will see

    // Convert all event times to incremental numbers of milliseconds. We use integers to count
    // milliseconds, insead of normal doubles, to avoid cumulative roundoff error (since 0.001
    // can't be represented exactly in floating point.)
    uint64_t lastMillis = 0;
    for (NSMutableDictionary* event in events) {
        CFAbsoluteTime tnew = [event[@"t"] doubleValue];
        [event removeObjectForKey: @"t"];
        uint64_t millis = (uint64_t)((tnew - time0) * 1000.0);
        if (millis > lastMillis)
            event[@"dt"] = @(millis - lastMillis);
        lastMillis = millis;
    }
    NSDictionary* doc = @{@"_id": docID, @"type": _docType, @"t0": time0String, @"events": events};

    // Now add to the queue of docs to be inserted:
    BOOL firstDoc = NO;
    @synchronized(self) {
        if (!_docsToAdd) {
            _docsToAdd = [NSMutableArray new];
            firstDoc = YES;
        }
        [_docsToAdd addObject: doc];
    }
    if (firstDoc && !_synchronousFlushing) {
        [_db doAsync: ^{
            [self saveQueuedDocs];
        }];
    }
}


// Must be called on db thread
- (BOOL) saveQueuedDocs {
    NSArray* docs;
    @synchronized(self) {
        docs = _docsToAdd;
        _docsToAdd = nil;
    }
    if (docs.count == 0)
        return YES;
    __block BOOL ok = YES;
    return [_db inTransaction: ^BOOL{
        for (CBLJSONDict *doc in docs) {
            NSError* error;
            NSString* docID = doc[@"_id"];
            if (![_db[docID] putProperties: doc error: &error]) {
                Warn(@"CBLTimeSeries: Couldn't save events to '%@': %@", docID, error);
                self.lastError = error;
                ok = NO;
            }
        }
        return YES;
    }] && ok;
}


#pragma mark - REPLICATION:


- (CBLReplication*) createPushReplication: (NSURL*)remoteURL
                          purgeWhenPushed: (BOOL)purgeWhenPushed
{
    CBLReplication* push = [_db createPushReplication: remoteURL];
    [_db setFilterNamed: @"com.couchbase.DocIDPrefix"
                asBlock: ^BOOL(CBLSavedRevision *revision, CBLJSONDict *params) {
        return [revision.document.documentID hasPrefix: params[@"prefix"]];
    }];
    push.filter = @"com.couchbase.DocIDPrefix";
    push.filterParams = @{@"prefix": _docIDPrefix};
    push.customProperties = @{@"allNew": @YES, @"purgePushed": @(purgeWhenPushed)};
    return push;
}


#pragma mark - QUERYING:


+ (BOOL) enumerateEventsInDocument: (CBLJSONDict*)doc
                        usingBlock: (CBLTimeSeriesEnumerationBlock)block
{
    EventArray* events = $castIf(NSArray, doc[@"events"]);
    NSDate* startDate = [CBLJSON dateWithJSONObject: doc[@"t0"]];
    if (!events || !startDate)
        return NO;
    CFAbsoluteTime start = dateToTime(startDate);
    double millis = 0;
    BOOL stop = NO;
    for (CBLJSONDict* event in events) {
        if (![event isKindOfClass: [NSDictionary class]])
            return NO;
        millis += [$castIf(NSNumber, event[@"dt"]) doubleValue];
        block(event, start + millis/1000.0, &stop);
        if (stop)
            break;
    }
    return YES;
}


// Returns an array of events starting at time t0 and continuing to the end of the document.
// If t0 is before the earliest recorded time, or falls between two documents, returns @[].
- (EventArray*) eventsFromDocForTime: (CFAbsoluteTime)t0
                           startTime: (CFAbsoluteTime*)outStartTime
                               error: (NSError**)outError {
    // Get the doc containing time t0. To do this we have to search _backwards_ since the doc ID
    // probably has a time before t0:
    CBLQuery* q = [_db createAllDocumentsQuery];
    q.startKey = [self docIDForTime: t0];
    q.descending = YES;
    q.limit = 1;
    q.prefetch = YES;
    __block CBLQueryEnumerator* e = [q run: outError];
    if (!e)
        return nil;
    CBLQueryRow* row = e.nextRow;
    if (!row)
        return @[];
    NSDictionary* document = row.document.properties;
    EventArray* events = document[@"events"];

    // Now find the first event with t ≥ t0:
    __block NSUInteger i0 = 0;
    [[self class] enumerateEventsInDocument: document
                                 usingBlock: ^(CBLJSONDict* event, CFAbsoluteTime time, BOOL* stop)
    {
        if (time >= t0) {
            *outStartTime = time - [event[@"dt"] doubleValue] / 1000.0;
            *stop = YES;
        } else {
            i0++;
        }
    }];
    return [events subarrayWithRange: NSMakeRange(i0, events.count-i0)];
}


- (NSEnumerator<CBLJSONDict*>*) eventsFromDate: (NSDate*)startDate
                                        toDate: (NSDate*)endDate
                                         error: (NSError**)outError
{
    // Get the first series from the doc containing t0 (if any):
    __block EventArray* curSeries = nil;
    __block CFAbsoluteTime baseTime = 0;
    if (startDate) {
        curSeries = [self eventsFromDocForTime: dateToTime(startDate)
                                     startTime: &baseTime
                                         error: outError];
        if (!curSeries)
            return nil;
    }

    // Start forwards query:
    CBLQuery* q = [_db createAllDocumentsQuery];
    CFAbsoluteTime queryStartTime;
    if (curSeries.count > 0) {
        double millis = 0.0;
        for (NSDictionary* event in curSeries)
            millis += [event[@"dt"] doubleValue];
        queryStartTime = baseTime + millis/1000.0;
        q.inclusiveStart = NO;
    } else {
        queryStartTime = dateToTime(startDate);
    }
    CFAbsoluteTime endTime = dateToTime(endDate); // invalid if endDate==nil

    CBLQueryEnumerator* e = nil;
    if (!endDate || queryStartTime < endTime) {
        q.startKey = queryStartTime > 0 ? [self docIDForTime: queryStartTime] : nil;
        q.endKey   = endDate ? [self docIDForTime: endTime] : nil;
        e = [q run: outError];
        if (!e)
            return nil;
    }

    // OK, here is the block for the enumerator:
    __block NSUInteger curIndex = 0;
    __block double millis = 0.0;
    return [[CBLTimeSeriesEnumerator alloc] initWithBlock: ^CBLJSONDict*{
        while (curIndex >= curSeries.count) {
            // Go to the next document:
            CBLQueryRow* row = e.nextRow;
            if (!row)
                return nil;
            curSeries = row.document[@"events"];
            curIndex = 0;
            baseTime = jsonToTime(row.document[@"t0"]);
            millis = 0.0;
        }
        // Return the next event from curSeries:
        CBLJSONDict* event = curSeries[curIndex++];
        millis += [event[@"dt"] doubleValue];
        CFAbsoluteTime time = baseTime + millis / 1000.0;
        if (endDate && time > endTime) {
            return nil;
        }
        NSMutableDictionary* result = [event mutableCopy];
        [result removeObjectForKey: @"dt"];
        result[@"t"] = timeToDate(time);
        return result;
    }];
}


@end



// Internal enumerator implementation whose -nextObject method just calls a block
@implementation CBLTimeSeriesEnumerator
{
    CBLJSONDict* (^_block)();
}

- (id) initWithBlock: (CBLJSONDict*(^)())block
{
    self = [super init];
    if (self) {
        _block = block;
    }
    return self;
}

- (CBLJSONDict*) nextObject {
    if (!_block)
        return nil;
    id result = _block();
    if (!result)
        _block = nil;
    return result;
}

@end
