//
//  TunesPerfTest.mm
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/30/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "TunesPerfTest.h"
#import "Benchmark.hh"
#include <chrono>
#include <thread>

using namespace std::chrono;

#define PROFILING 0
#define VERBOSE   0

#define VerboseLog(LEVEL, FORMAT, ...) if (VERBOSE < LEVEL) { } else NSLog(FORMAT, ##__VA_ARGS__)

#if PROFILING
// Settings for use with Instruments: only run one iteration, and sleep for 0.5sec between
// sub-tests to make them easy to distinguish in the Instruments time trace.
static constexpr int kNumIterations = 1;
static constexpr auto kInterTestSleep = milliseconds(500);
#else
static constexpr int kNumIterations = 10;
static constexpr auto kInterTestSleep = milliseconds(0);
#endif


@implementation TunesPerfTest
{
    NSArray* _tracks;
    NSUInteger _documentCount;
    NSArray* _artists;
    Benchmark _importBench, _updatePlayCountBench, _updateArtistsBench, _indexArtistsBench,
              _queryArtistsBench, _queryIndexedArtistsBench,
              _queryAlbumsBench, _queryIndexedAlbumsBench,
              _indexFTSBench, _queryFTSBench;
}


- (void) setUp {
    // Pre-parse the JSON file:
    NSData *jsonData = [self dataFromResource: @"iTunesMusicLibrary" ofType: @"json"];
    NSString* json = [[NSString alloc] initWithData: jsonData encoding: NSUTF8StringEncoding];
    NSMutableArray *tracks = [NSMutableArray array];
    [json enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
        NSError* error;
        NSData* lineData = [line dataUsingEncoding: NSUTF8StringEncoding];
        id track = [NSJSONSerialization JSONObjectWithData: lineData options: 0 error: &error];
        Assert(track, @"Failed to parse JSON: %@", error);
        [tracks addObject: track];
    }];
    _tracks = tracks;
    _documentCount = _tracks.count;
}


- (void) pause {
    std::this_thread::sleep_for(kInterTestSleep);
}


- (void) test {
    unsigned numDocs = 0, numUpdates = 0, numArtists = 0, numAlbums = 0, numFTS = 0;
    for (int i = 0; i < kNumIterations; i++) {
        fprintf(stderr, "Starting iteration #%d...\n", i+1);
        @autoreleasepool {
            [self eraseDB];
            [self pause];
            numDocs = [self importLibrary];
            [self pause];
            [self reopenDB];
            [self pause];
            numUpdates = [self updateArtistNames];
            [self pause];

            numArtists = [self queryAllArtists: _queryArtistsBench];
            [self pause];
            numAlbums = [self queryAlbums: _queryAlbumsBench];
            [self pause];

            [self createArtistsIndex];
            [self pause];

            unsigned numArtists2 = [self queryAllArtists: _queryIndexedArtistsBench];
            Assert(numArtists2 == numArtists);
            [self pause];
            unsigned numAlbums2 = [self queryAlbums: _queryIndexedAlbumsBench];
            Assert(numAlbums2 == numAlbums);
            [self pause];

            numFTS = [self fullTextSearch];
            [self pause];
        }
    }
    fprintf(stderr, "\n\n");
    fprintf(stderr, "Import %5d docs:  ", numDocs); _importBench.printReport();
    fprintf(stderr, "                    "); _importBench.printReport(1.0/numDocs, "doc");
    fprintf(stderr, "                     Rate: %.0f docs/sec\n", numDocs/_importBench.median());
    if (!_updatePlayCountBench.empty()) {
        fprintf(stderr, "Update all docs:    "); _updatePlayCountBench.printReport();
        fprintf(stderr, "                    "); _updatePlayCountBench.printReport(1.0/numDocs, "update");
    }
    fprintf(stderr, "Update %4d docs:   ", numUpdates); _updateArtistsBench.printReport();
    fprintf(stderr, "                     Rate: %.0f docs/sec\n", numUpdates/_updateArtistsBench.median());
    fprintf(stderr, "                    "); _updateArtistsBench.printReport(1.0/numUpdates, "update");
    fprintf(stderr, "Query %4d artists: ", numArtists); _queryArtistsBench.printReport();
    fprintf(stderr, "                    "); _queryArtistsBench.printReport(1.0/numArtists, "row");
    fprintf(stderr, "Query %4d albums:  ", numAlbums); _queryAlbumsBench.printReport();
    fprintf(stderr, "                    "); _queryAlbumsBench.printReport(1.0/numArtists, "artist");
    fprintf(stderr, "Index by artist:    "); _indexArtistsBench.printReport();
    fprintf(stderr, "                    "); _indexArtistsBench.printReport(1.0/numDocs, "doc");
    fprintf(stderr, "Re-query artists:   "); _queryIndexedArtistsBench.printReport();
    fprintf(stderr, "                    "); _queryIndexedArtistsBench.printReport(1.0/numArtists, "row");
    fprintf(stderr, "Re-query albums:    "); _queryIndexedAlbumsBench.printReport();
    fprintf(stderr, "                    "); _queryIndexedAlbumsBench.printReport(1.0/numArtists, "artist");
    fprintf(stderr, "FTS indexing:       "); _indexFTSBench.printReport();
    fprintf(stderr, "                    "); _indexFTSBench.printReport(1.0/numDocs, "doc");
    fprintf(stderr, "FTS query:          "); _queryFTSBench.printReport();
    fprintf(stderr, "                    "); _queryFTSBench.printReport(1.0/numFTS, "row");
}


/** Adds all the tracks to the database. */
- (unsigned) importLibrary {
    @autoreleasepool {
    NSArray* keysToCopy = nil; /*@[@"Name", @"Artist", @"Album", @"Genre", @"Year", @"Total Time", @"Track Number", @"Compilation"];*/

    _importBench.start();
    _documentCount = 0;
    __block CFAbsoluteTime startTransaction;
    BOOL ok = [self.db inBatch: NULL do: ^{
        for (NSDictionary* track in _tracks) {
            NSString* trackType = track[@"Track Type"];
            if (![trackType isEqual: @"File"] && ![trackType isEqual: @"Remote"])
                continue;
            @autoreleasepool {
                NSString* documentID = track[@"Persistent ID"];
                if (!documentID)
                    continue;

                NSMutableDictionary* props;
                if (keysToCopy) {
                    props = [NSMutableDictionary dictionary];
                    for(NSString* key in keysToCopy) {
                        id value = track[key];
                        if (value)
                            props[key] = value;
                    }
                } else {
                    props = [track mutableCopy];
                }

                ++_documentCount;
                /*NSLog(@"#%4u: %@ \"%@\"",
                        count, [props objectForKey: @"Artist"], [props objectForKey: @"Name"]);*/
                CBLDocument* doc = [CBLDocument documentWithID: documentID];
                [doc setDictionary: props];
                NSError* error;
                if (![self.db saveDocument: doc error: &error])
                    Assert(NO, @"Couldn't save doc: %@", error);
            }
        }
        startTransaction = CFAbsoluteTimeGetCurrent();
    }];
    __unused double commitTime = CFAbsoluteTimeGetCurrent() - startTransaction;
    __unused double t = _importBench.stop();
    Assert(ok, @"Batch operation failed");
    VerboseLog(1, @"Imported %u documents in %.06f sec (import %g, commit %g)", (unsigned)_documentCount, t, t - commitTime, commitTime);
    return (unsigned)_documentCount;
    }
}


- (void) loadOneDocument {
    NSString* docID = [_tracks[4321] objectForKey: @"Persistent ID"];
    CBLDocument* doc = [self.db documentWithID: docID];
    __unused NSDictionary* properties = doc.toDictionary;
}


// Increments the "Play Count" property of every document in the database.
- (unsigned) updatePlayCounts {
    @autoreleasepool {
    _updatePlayCountBench.start();
    __block unsigned count = 0;
    BOOL ok = [self.db inBatch: NULL do: ^{
        for (CBLDocument* doc in self.db.allDocuments) {
            @autoreleasepool {
                NSInteger playCount = [doc integerForKey: @"Play Count"];
                [doc setObject: @(playCount + 1) forKey: @"Play Count"];
                Assert([self.db saveDocument: doc error: NULL], @"Save failed");
                count++;
            }
        }
    }];
    __unused double t = _updatePlayCountBench.stop();
    Assert(ok, @"Batch operation failed");
    VerboseLog(1, @"Updated %u documents' playCount in %.06f sec", count, t);
    return count;
    }
}


// Strips "The " from the names of all artists.
- (unsigned) updateArtistNames {
    @autoreleasepool {
    _updateArtistsBench.start();
    __block unsigned count = 0;
    __block CFAbsoluteTime startTransaction;
    BOOL ok = [self.db inBatch: NULL do: ^{
        for (CBLDocument* doc in self.db.allDocuments) {
            @autoreleasepool {
                NSString* artist = [doc stringForKey: @"Artist"];
                if ([artist hasPrefix: @"The "]) {
                    [doc setObject: [artist substringFromIndex: 4] forKey: @"Artist"];
                    Assert([self.db saveDocument: doc error: NULL], @"Save failed");
                    count++;
                }
            }
        }
        startTransaction = CFAbsoluteTimeGetCurrent();
    }];
    __unused double commitTime = CFAbsoluteTimeGetCurrent() - startTransaction;
    __unused double t = _updateArtistsBench.stop();
    VerboseLog(1, @"Updated %u docs in %.06f sec (update %g, commit %g)", count, t, t - commitTime, commitTime);
    Assert(ok, @"Batch operation failed");
    return count;
    }
}


// Subroutine that runs a query and returns an array of the first 'returning' property
- (NSArray*) collectQueryResults: (CBLPredicateQuery*)query {
    @autoreleasepool {
        NSMutableArray* results = [NSMutableArray array];
        NSError* error = nil;
        for (CBLQueryRow* row in [query run: &error])
            [results addObject: row[0]];
        Assert(!error, @"Query failed: %@", error);
        return results;
    }
}


// Collects the names of all artists in the database using a query.
- (unsigned) queryAllArtists: (Benchmark&)bench {
    @autoreleasepool {
    CBLPredicateQuery* query = [self.db createQueryWhere: @"Artist != nil && Compilation == nil"];
    query.returning = @[@"Artist"];
    query.groupBy = @[@"Artist[cd]"];
    query.orderBy = @[@"Artist[cd]"];

    Assert([query check: NULL]);
    VerboseLog(1, @"%@", [query explain: NULL]);
    bench.start();
    _artists = [self collectQueryResults: query];
    __unused double t = bench.stop();
    VerboseLog(1, @"Artist query took %.06f sec", t);

    VerboseLog(2, @"%u artists:\n'%@'", (unsigned)_artists.count, [_artists componentsJoinedByString: @"'\n'"]);
    VerboseLog(1, @"%u artists, from %@ to %@", (unsigned)_artists.count, _artists.firstObject, _artists.lastObject);
    AssertEq(_artists.count, 1111u);
    return (unsigned)_artists.count;
    }
}


// Creates an index on the Artist property (case-insensitive.)
- (void) createArtistsIndex {
    @autoreleasepool {
        VerboseLog(1, @"Indexing artists...");
        _indexArtistsBench.start();
        CBLQueryCollation* collation = [CBLQueryCollation unicodeWithLocale: nil
                                                                 ignoreCase: YES
                                                              ignoreAccents: YES];
        CBLQueryExpression* artist = [[CBLQueryExpression property: @"Artist"] collate: collation];
        CBLQueryExpression* comp = [CBLQueryExpression property: @"Compilation"];
        CBLIndex *index = [CBLIndex valueIndexOn: @[[CBLValueIndexItem expression: artist],
                                                    [CBLValueIndexItem expression: comp]]];
        Assert(([self.db createIndex: index withName: @"byArtist" error: NULL]));
        __unused double t = _indexArtistsBench.stop();
        VerboseLog(1, @"Indexed artists in %.06f sec", t);
    }
}


// Queries to find the albums by every artist.
- (unsigned) queryAlbums: (Benchmark&)bench {
    @autoreleasepool {
    CBLPredicateQuery* query = [self.db createQueryWhere: @"Artist ==[cd] $ARTIST && Compilation == nil"];
    query.returning = @[@"Album"];
    query.groupBy = @[@"Album[cd]"];
    query.orderBy = @[@"Album[cd]"];

    Assert([query check: NULL]);
    VerboseLog(1, @"%@", [query explain: NULL]);
    bench.start();

    // Run one query per artist to find their albums. We could write a single query to get all of
    // these results at once, but I want to benchmark running a CBLQuery lots of times...
    unsigned albumCount = 0;
    for (NSString* artist in _artists) {
        @autoreleasepool {
            query.parameters = @{@"ARTIST": artist};
            NSArray* albums = [self collectQueryResults: query];
            albumCount += albums.count;
            //NSLog(@"Albums by %@: '%@'", artist, [albums componentsJoinedByString: @"', '"]);
        }
    }
    __unused double t = bench.stop();
    VerboseLog(1, @"%u albums total, in %.06f sec", albumCount, t);
    AssertEq(albumCount, 1886u);
    return albumCount;
    }
}


// Finds all the song titles containing the word "rock", using Full-Text Search.
- (unsigned) fullTextSearch {
    @autoreleasepool {
        NSError *error;
        _indexFTSBench.start();
        CBLQueryExpression* nameExpr = [CBLQueryExpression property: @"Name"];
        CBLIndex *index = [CBLIndex ftsIndexOn: [CBLFTSIndexItem expression: nameExpr]
                                       options: nil];
        Assert(([self.db createIndex: index withName: @"nameFTS" error: &error]),
               @"Full-text indexing failed: %@", error);
        _indexFTSBench.stop();
        [self pause];

        CBLPredicateQuery* query = [self.db createQueryWhere: @"Name matches 'Rock'"];
        query.returning = @[@"Artist", @"Album", @"Name"];
        query.orderBy = @[@"Artist[cd]", @"Album[cd]"];
        Assert([query check: &error], @"FTS query failed: %@", error);
        VerboseLog(2, @"%@", [query explain: NULL]);
        [self pause];

        _queryFTSBench.start();
        NSMutableArray* results = [NSMutableArray array];
        for (CBLFullTextQueryRow* row in [query run: &error]) {
            @autoreleasepool {
                [results addObject: row.fullTextMatched];
            }
        }
        __unused double t = _queryFTSBench.stop();
        Assert(!error, @"Query failed: %@", error);

        VerboseLog(2, @"%u 'rock' songs in %.06f sec: \"%@\"", (unsigned)results.count, t, [results componentsJoinedByString: @"\", \""]);
        VerboseLog(1, @"%u 'rock' songs in %.06f sec", (unsigned)results.count, t);
        AssertEq(results.count, 30u);
        return (unsigned)results.count;
    }
}


@end
