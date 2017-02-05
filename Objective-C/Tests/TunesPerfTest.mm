//
//  TunesPerfTest.mm
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/30/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "TunesPerfTest.h"
#import "Benchmark.hh"


// Define this to limit the number of docs imported into the database.
//#define kMaxDocsToImport 1000


@implementation TunesPerfTest
{
    NSArray* _tracks;
    NSUInteger _documentCount;
    Benchmark _importBench, _updatePlayCountBench, _queryArtistsBench, _indexArtistsBench, _queryIndexedArtistsBench;
}


- (void) setUp {
    NSData *jsonData = [self dataFromResource: @"iTunesMusicLibrary" ofType: @"json"];
    _tracks = [NSJSONSerialization JSONObjectWithData: jsonData options: 0 error: NULL];
    _documentCount = _tracks.count;
}


- (void) test {
    unsigned numDocs = 0, numPlayCounts = 0, numArtists = 0;
    for (int i = 0; i < 10; i++) {
        fprintf(stderr, "Starting iteration #%d...\n", i+1);
        @autoreleasepool {
            [self eraseDB];
            numDocs = [self importLibrary];
            [self reopenDB];
            numPlayCounts = [self updatePlayCounts];
            numArtists = [self queryAllArtists: _queryArtistsBench];
            [self createArtistsIndex];
            [self queryAllArtists: _queryIndexedArtistsBench];
        }
    }
    fprintf(stderr, "Import:             "); _importBench.printReport();
    fprintf(stderr, "                    "); _importBench.printReport(1.0/numDocs, "doc");
    fprintf(stderr, "Update play counts: "); _updatePlayCountBench.printReport();
    fprintf(stderr, "                    "); _updatePlayCountBench.printReport(1.0/numPlayCounts, "update");
    fprintf(stderr, "Query %d artists: ", numArtists); _queryArtistsBench.printReport();
    fprintf(stderr, "                    "); _queryArtistsBench.printReport(1.0/numArtists, "row");
    fprintf(stderr, "Index artists:      "); _indexArtistsBench.printReport();
    fprintf(stderr, "Query %d artists: ", numArtists); _queryIndexedArtistsBench.printReport();
    fprintf(stderr, "                    "); _queryIndexedArtistsBench.printReport(1.0/numArtists, "row");
}


- (unsigned) importLibrary {
    _importBench.start();
    NSArray* keysToCopy = keysToCopy = @[@"Name", @"Artist", @"Album", @"Genre", @"Year",
                                         @"Total Time", @"Track Number", @"Compilation"];

    _documentCount = 0;
    BOOL ok = [self.db inBatch: NULL do: ^{
        for (NSDictionary* track in _tracks) {
#ifdef kMaxDocsToImport
            if (count >= kMaxDocsToImport) {
                NSLog(@"***** Stopping after %d tracks *****", kMaxDocsToImport);
                break;
            }
#endif
            NSString* trackType = track[@"Track Type"];
            if (![trackType isEqual: @"File"] && ![trackType isEqual: @"Remote"])
                continue;
            @autoreleasepool {
                NSString* documentID = track[@"Persistent ID"];
                if (!documentID)
                    continue;
                NSMutableDictionary* props = [NSMutableDictionary dictionary];
                for(NSString* key in keysToCopy) {
                    id value = track[key];
                    if (value)
                        props[key] = value;
                }
                ++_documentCount;
                /*NSLog(@"#%4u: %@ \"%@\"",
                        count, [props objectForKey: @"Artist"], [props objectForKey: @"Name"]);*/
                CBLDocument* doc = self.db[documentID];
                doc.properties = props;

                NSError* error;
                if (![doc save: &error])
                    NSAssert(NO, @"Couldn't save doc: %@", error);
            }
        }
    }];
    _importBench.stop();
    NSAssert(ok, @"Batch operation failed");
    return (unsigned)_documentCount;
}


- (void) loadOneDocument {
    NSString* docID = [_tracks[4321] objectForKey: @"Persistent ID"];
    CBLDocument* doc = [self.db documentWithID: docID];
    __unused NSDictionary* properties = doc.properties;
}


- (unsigned) updatePlayCounts {
    _updatePlayCountBench.start();
    __block unsigned count = 0;
    BOOL ok = [self.db inBatch: NULL do: ^{
        for (CBLDocument* doc in self.db.allDocuments) {
            NSInteger playCount = [doc integerForKey: @"playCount"];
            [doc setInteger: playCount + 1 forKey: @"playCount"];
            NSAssert([doc save: NULL], @"Save failed");
            count++;
        }
    }];
    _updatePlayCountBench.stop();
    NSAssert(ok, @"Batch operation failed");
//    NSLog(@"Updated %u documents' playCount", count);
    return count;
}


- (unsigned) updateArtistNames {
    __block unsigned count = 0;
    [self.db inBatch: NULL do: ^{
        for (CBLDocument* doc in self.db.allDocuments) {
            NSString* artist = [doc stringForKey: @"Artist"];
#if 1
            if ([artist hasPrefix: @"The "])
                doc[@"Artist"] = [artist substringFromIndex: 4];
            NSInteger playCount = [doc integerForKey: @"playCount"];
            [doc setInteger: playCount + 1 forKey: @"playCount"];
#else
            if (![artist hasPrefix: @"The "])
                continue;
            doc[@"Artist"] = [artist substringFromIndex: 4];
#endif
            NSAssert([doc save: NULL], @"Save failed");
            count++;
        }
    }];
    return count;
}


- (unsigned) updateTrackTimes {
    __block unsigned count = 0;
    [self.db inBatch: NULL do: ^{
        for (CBLDocument* doc in self.db.allDocuments) {
            double time = [doc doubleForKey: @"Total Time"];
            [doc setDouble: time + 1.0 forKey: @"Total Time"];
            NSAssert([doc save: NULL], @"Save failed");
            count++;
        }
    }];
    return count;
}


- (unsigned) queryAllArtists: (Benchmark&)bench {
    CBLQuery* query = [self.db createQueryWhere: nil];
    query.groupBy = query.orderBy = @[@"TERNARY(Compilation == true, '--Compilation--', lowercase(Artist))"];
    query.returning = @[@"TERNARY(Compilation == true, '--Compilation--', Artist)"];
    Assert([query check: NULL]);
    NSLog(@"%@", [query explain: NULL]);
    bench.start();
    NSMutableArray* artists = [NSMutableArray array];
    NSError* error;
    for (CBLQueryRow* row in [query run: &error]) {
        NSString* artist = row[0];
        [artists addObject: artist];
        //NSLog(@"artist: %@", artist);//TEMP
    }
    bench.stop();
    NSLog(@"%u artists, from %@ to %@", (unsigned)artists.count, artists.firstObject, artists.lastObject);
    return (unsigned)artists.count;
}


- (void) createArtistsIndex {
    NSLog(@"Indexing artists...");
    _indexArtistsBench.start();
    Assert([self.db createIndexOn: @[@"TERNARY(Compilation == true, '--Compilation--', lowercase(Artist))"] error: NULL]);
    _indexArtistsBench.stop();
}


#if 0
- (void) defineView {
    // Define a map function that emits keys of the form [artist, album, track#, trackname]
    // and values that are the track time in milliseconds;
    // and a reduce function that adds up track times.
    CBLView* view = [self.db viewNamed: kArtistsViewName];
    [view setMapBlock: MAPBLOCK({
        NSString* artist = doc[@"Artist"];
        NSString* name = doc[@"Name"];
        if (artist && name) {
            if ([doc[@"Compilation"] boolValue]) {
                artist = @"-Compilations-";
            }
            emit(@[artist,
                   doc[@"Album"] ?: [NSNull null],
                   doc[@"Track Number"] ?: [NSNull null],
                   name,
                   @1],
                 doc[@"Total Time"]);
        }
    }) reduceBlock: REDUCEBLOCK({
        return [CBLView totalValues: values];
    })
              version: @"3"];
    //    view.indexEagerly = kEager;

    // Another view whose keys are [album, artist, track#, trackname]
    CBLView* albumsView = [self.db viewNamed: kAlbumsViewName];
    [albumsView setMapBlock: MAPBLOCK({
        NSString* album = doc[@"Album"];
        if (album) {
            NSString* artist = doc[@"Artist"];
            if ([doc[@"Compilation"] boolValue])
                artist = @"-Compilations-";
            emit(@[album,
                   artist ?: [NSNull null],
                   doc[@"Track Number"] ?: [NSNull null],
                   doc[@"Name"] ?: @"",
                   @1],
                 doc[@"Total Time"]);
        }
    }) reduceBlock: REDUCEBLOCK({
        return [CBLView totalValues: values];
    })
                    version: @"1"];
    //    albumsView.indexEagerly = kEager;


    // A simple view that accesses fewer properties:
    CBLView* trackNameView = [self.db viewNamed: kTracksViewName];
    [trackNameView setMapBlock: MAPBLOCK({
        NSString* name = doc[@"Name"];
        if (name)
            emit(name, nil);
    }) reduceBlock: REDUCEBLOCK({
        return [CBLView totalValues: values];
    })
                       version: @"1"];
    //    trackNameView.indexEagerly = kEager;
}

- (void) indexView: (NSString*)name {
    CBLView* view = [self.db viewNamed: name];
    UInt64 lastChanged = view.lastSequenceChangedAt;
    CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();
    [view updateIndex];
    NSLog(@"%.3f sec -- Indexing '%@' view (changed was %lld, now %lld)",
     (CFAbsoluteTimeGetCurrent() - startTime), name,
     lastChanged, view.lastSequenceChangedAt);
}

- (void) indexTracks {
    CFAbsoluteTime totalStartTime = CFAbsoluteTimeGetCurrent();
    [self indexView: kArtistsViewName];
    [self indexView: kAlbumsViewName];
    NSLog(@"%.3f sec -- Total indexing",
     (CFAbsoluteTimeGetCurrent() - totalStartTime));
    [self indexView: kTracksViewName];
}


- (void) queryTracks {
    static const NSUInteger kArtistCount = 1167;

    // The artists query is grouped to level 1, so it collapses all keys with the same artist.
    CBLView* view = [self.db viewNamed: kArtistsViewName];
    CBLQuery* q = [view createQuery];
    q.groupLevel = 1;
    NSMutableArray* artists = [NSMutableArray arrayWithCapacity: kArtistCount];

    CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();
    for (CBLQueryRow* row in [q run: NULL]) {
        NSString* artist = row.key0;
        [artists addObject: artist];
    }
    NSLog(@"%.3f sec -- Grouped query (%lu rows)",
     (CFAbsoluteTimeGetCurrent() - startTime), (unsigned long)artists.count);
    //    Assert(artists.count == kArtistCount, @"Wrong artist count %ld; should be %ld",
    //             (unsigned long)artists.count, (unsigned long)kArtistCount);
}


#ifdef TEST_FULL_TEXT_INDEX
- (void) indexFullText {
    // Another view that creates a full-text index of everything:
    CBLView* fullTextView = [self.db viewNamed: @"fullText"];
#ifdef NEW_FTS_API
    fullTextView.indexType = kCBLFullTextIndex;
#endif
    [fullTextView setMapBlock: MAPBLOCK({
#ifdef NEW_FTS_API
        emit(doc[@"Artist"], nil);
        emit(doc[@"Album"], nil);
        emit(doc[@"Name"], nil);
#else
        if (doc[@"Artist"]) emit(CBLTextKey(doc[@"Artist"]), nil);
        if (doc[@"Album"])  emit(CBLTextKey(doc[@"Album"]), nil);
        if (doc[@"Name"])   emit(CBLTextKey(doc[@"Name"]), nil);
#endif
    })
                      version: @"1"];

    CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();
    [fullTextView updateIndex];
    NSLog(@"%.3f sec -- Indexing full-text view",
     (CFAbsoluteTimeGetCurrent() - startTime));
}
#endif

#endif


@end
