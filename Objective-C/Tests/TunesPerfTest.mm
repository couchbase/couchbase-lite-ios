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

#if PROFILING
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
    Benchmark _importBench, _updatePlayCountBench, _queryArtistsBench, _indexArtistsBench,
              _queryIndexedArtistsBench, _queryAlbumsBench, _indexFTSBench, _queryFTSBench;
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
            [self createArtistsIndex];
            [self pause];
            [self queryAllArtists: _queryIndexedArtistsBench];
            [self pause];
            numAlbums = [self queryAlbums: _queryAlbumsBench];
            [self pause];
            numFTS = [self fullTextSearch];
            [self pause];
        }
    }
    fprintf(stderr, "\n\n");
    fprintf(stderr, "Import %5d docs:  ", numDocs); _importBench.printReport();
    fprintf(stderr, "                    "); _importBench.printReport(1.0/numDocs, "doc");
    fprintf(stderr, "Update %4d docs:   ", numUpdates); _updatePlayCountBench.printReport();
    fprintf(stderr, "                    "); _updatePlayCountBench.printReport(1.0/numUpdates, "update");
    fprintf(stderr, "Query %4d artists: ", numArtists); _queryArtistsBench.printReport();
    fprintf(stderr, "                    "); _queryArtistsBench.printReport(1.0/numArtists, "row");
    fprintf(stderr, "Index by artist:    "); _indexArtistsBench.printReport();
    fprintf(stderr, "                    "); _indexArtistsBench.printReport(1.0/numDocs, "doc");
    fprintf(stderr, "Query %4d artists: ", numArtists); _queryIndexedArtistsBench.printReport();
    fprintf(stderr, "                    "); _queryIndexedArtistsBench.printReport(1.0/numArtists, "row");
    fprintf(stderr, "Query %4d albums:  ", numAlbums); _queryAlbumsBench.printReport();
    fprintf(stderr, "                    "); _queryAlbumsBench.printReport(1.0/numArtists, "artist");
    fprintf(stderr, "FTS indexing:       "); _indexFTSBench.printReport();
    fprintf(stderr, "                    "); _indexFTSBench.printReport(1.0/numDocs, "doc");
    fprintf(stderr, "FTS query:          "); _queryFTSBench.printReport();
    fprintf(stderr, "                    "); _queryFTSBench.printReport(1.0/numFTS, "row");
}


/** Adds all the tracks to the database. */
- (unsigned) importLibrary {
    NSArray* keysToCopy = nil; /*@[@"Name", @"Artist", @"Album", @"Genre", @"Year", @"Total Time", @"Track Number", @"Compilation"];*/

    _importBench.start();
    _documentCount = 0;
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
    }];
    _importBench.stop();
    Assert(ok, @"Batch operation failed");
    return (unsigned)_documentCount;
}


- (void) loadOneDocument {
    NSString* docID = [_tracks[4321] objectForKey: @"Persistent ID"];
    CBLDocument* doc = [self.db documentWithID: docID];
    __unused NSDictionary* properties = doc.toDictionary;
}


// Increments the "Play Count" property of every document in the database.
- (unsigned) updatePlayCounts {
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
    _updatePlayCountBench.stop();
    Assert(ok, @"Batch operation failed");
//    NSLog(@"Updated %u documents' playCount", count);
    return count;
}


// Strips "The " from the names of all artists.
- (unsigned) updateArtistNames {
    _updatePlayCountBench.start();
    __block unsigned count = 0;
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
    }];
    _updatePlayCountBench.stop();
    Assert(ok, @"Batch operation failed");
    return count;
}


// Subroutine that runs a query and returns an array of the first 'returning' property
- (NSArray*) collectQueryResults: (CBLPredicateQuery*)query {
    NSMutableArray* results = [NSMutableArray array];
    NSError* error = nil;
    for (CBLQueryRow* row in [query run: &error])
        [results addObject: row[0]];
    Assert(!error, @"Query failed: %@", error);
    return results;
}


// Collects the names of all artists in the database using a query.
- (unsigned) queryAllArtists: (Benchmark&)bench {
    CBLPredicateQuery* query = [self.db createQueryWhere: @"Artist != nil && Compilation == nil"];
    query.returning = @[@"Artist"];
    query.groupBy = @[@"lowercase(Artist)"];
    query.orderBy = @[@"lowercase(Artist)"];

    Assert([query check: NULL]);
//    NSLog(@"%@", [query explain: NULL]);
    bench.start();
    _artists = [self collectQueryResults: query];
    bench.stop();
    NSLog(@"%u artists, from %@ to %@", (unsigned)_artists.count, _artists.firstObject, _artists.lastObject);
    AssertEq(_artists.count, 1115u);
    return (unsigned)_artists.count;
}


// Creates an index on the Artist property (case-insensitive.)
- (void) createArtistsIndex {
    NSLog(@"Indexing artists...");
    _indexArtistsBench.start();
#if 1
    Assert(([self.db createIndexOn: @[@"lowercase(Artist)", @"Compilation"] error: NULL]));
#else
    Assert([self.db createIndexOn: @[@"TERNARY(Compilation == true, '--Compilation--', lowercase(Artist))"] error: NULL]);
#endif
    _indexArtistsBench.stop();
}


// Queries to find the albums by every artist.
- (unsigned) queryAlbums: (Benchmark&)bench {
    CBLPredicateQuery* query = [self.db createQueryWhere: @"lowercase(Artist) == lowercase($ARTIST) && Compilation == nil"];
    query.returning = @[@"Album"];
    query.groupBy = @[@"lowercase(Album)"];
    query.orderBy = @[@"lowercase(Album)"];

    Assert([query check: NULL]);
//    NSLog(@"%@", [query explain: NULL]);
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
    bench.stop();
    NSLog(@"%u albums total", albumCount);
    AssertEq(albumCount, 1887u);
    return albumCount;
}


// Finds all the song titles containing the word "rock", using Full-Text Search.
- (unsigned) fullTextSearch {
    NSError *error;
    _indexFTSBench.start();
    Assert(([self.db createIndexOn: @[@"Name"]
                              type: kCBLFullTextIndex options: NULL
                             error: &error]),
             @"Full-text indexing failed: %@", error);
    _indexFTSBench.stop();

    CBLPredicateQuery* query = [self.db createQueryWhere: @"Name matches 'Rock'"];
    query.returning = @[@"Artist", @"Album", @"Name"];
    query.orderBy = @[@"lowercase(Artist)", @"lowercase(Album)"];
//    NSLog(@"%@", [query explain: NULL]);

    _queryFTSBench.start();
    NSMutableArray* results = [NSMutableArray array];
    for (CBLFullTextQueryRow* row in [query run: &error])
        [results addObject: row.fullTextMatched];
    _queryFTSBench.stop();
    Assert(!error, @"Query failed: %@", error);

//    NSLog(@"%u 'rock' songs: \"%@\"", (unsigned)results.count, [results componentsJoinedByString: @"\", \""]);
    AssertEq(results.count, 30u);
    return (unsigned)results.count;
}


@end
