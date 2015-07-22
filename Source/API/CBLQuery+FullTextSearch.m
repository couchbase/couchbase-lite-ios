//
//  CBLQuery+FullTextSearch.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 9/21/13.
//  Copyright (c) 2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBLInternal.h"
#import "CBLQuery+FullTextSearch.h"
#import "CBLView+Internal.h"


static NSUInteger utf8BytesToChars(const void* bytes, NSUInteger byteStart, NSUInteger byteEnd);


@interface CBLFTSMatch : NSObject
{
    @public
    NSUInteger term;
    NSRange textRange;
}
@end

@implementation CBLFTSMatch

- (NSComparisonResult) compare: (CBLFTSMatch*)other {
    return (NSInteger)textRange.location - (NSInteger)other->textRange.location;
}

@end



@implementation CBLQuery (FullTextSearch)

- (NSString*) fullTextQuery                         {return _fullTextQuery;}
- (void) setFullTextQuery:(NSString *)fullTextQuery {_fullTextQuery = [fullTextQuery copy];}
- (BOOL) fullTextSnippets                           {return _fullTextSnippets;}
- (void) setFullTextSnippets:(BOOL)fullTextSnippets {_fullTextSnippets = fullTextSnippets;}
- (BOOL) fullTextRanking                            {return _fullTextRanking;}
- (void) setFullTextRanking:(BOOL)fullTextRanking   {_fullTextRanking = fullTextRanking;}

@end



@implementation CBLFullTextQueryRow
{
    UInt64 _fullTextID;
    NSString* _snippet;
    NSMutableArray* _matches;
}

@synthesize snippet=_snippet, relevance=_relevance;

- (instancetype) initWithDocID: (NSString*)docID
                      sequence: (SequenceNumber)sequence
                    fullTextID: (UInt64)fullTextID
                         value: (id)value
                       storage: (id<CBL_QueryRowStorage>)storage
{
    self = [super initWithDocID: docID sequence: sequence key: $null value: value
                  docRevision: nil storage: storage];
    if (self) {
        _fullTextID = fullTextID;
        _matches = [[NSMutableArray alloc] initWithCapacity: 4];
    }
    return self;
}

- (void) addTerm: (NSUInteger)term atRange: (NSRange)range {
    CBLFTSMatch* match = [CBLFTSMatch new];
    match->term = term;
    match->textRange = range;
    [_matches addObject: match];
}


- (BOOL) containsAllTerms: (NSUInteger)termCount {
    if (termCount == 1)
        return YES;
    BOOL result = NO;
    if (self.matchCount >= termCount) {
        CFMutableBitVectorRef seen = CFBitVectorCreateMutable(NULL, termCount);
        NSUInteger termsSeen = 0;
        for (CBLFTSMatch* match in _matches) {
            if (!CFBitVectorGetBitAtIndex(seen, match->term)) {
                if (++termsSeen == termCount) {
                    result = YES;
                    break;
                }
                CFBitVectorSetBitAtIndex(seen, match->term, 1);
            }
        }
        CFRelease(seen);
    }
    if (result)
        [_matches sortUsingSelector: @selector(compare:)];
    return result;
}


- (NSData*) fullTextUTF8Data {
    return [self.storage fullTextForDocument: self.documentID
                                    sequence: self.sequenceNumber
                                  fullTextID: _fullTextID];
}

- (NSString*) fullText {
    NSData* data = self.fullTextUTF8Data;
    if (!data)
        return nil;
    return [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding];
}

- (NSUInteger) matchCount {
    return _matches.count;
}

- (NSUInteger) termIndexOfMatch: (NSUInteger)matchNumber {
    return ((CBLFTSMatch*)_matches[matchNumber])->term;
}

- (NSRange) textRangeOfMatch: (NSUInteger)matchNumber {
    CBLFTSMatch* match = _matches[matchNumber];
    NSUInteger byteStart  = match->textRange.location;
    NSUInteger byteLength = match->textRange.length;
    NSData* rawText = self.fullTextUTF8Data;
    return NSMakeRange(utf8BytesToChars(rawText.bytes, 0, byteStart),
                       utf8BytesToChars(rawText.bytes, byteStart, byteStart + byteLength));
}


- (NSString*) snippetWithWordStart: (NSString*)wordStart
                           wordEnd: (NSString*)wordEnd
{
    if (!_snippet)
        return nil;
    NSMutableString* snippet = [_snippet mutableCopy];
    [snippet replaceOccurrencesOfString: @"\001" withString: wordStart
                                options:NSLiteralSearch range:NSMakeRange(0, snippet.length)];
    [snippet replaceOccurrencesOfString: @"\002" withString: wordEnd
                                options:NSLiteralSearch range:NSMakeRange(0, snippet.length)];
    return snippet;
}


// Overridden to add FTS result info
- (NSDictionary*) asJSONDictionary {
    NSMutableDictionary* dict = [[super asJSONDictionary] mutableCopy];
    if (!dict[@"error"]) {
        [dict removeObjectForKey: @"key"];
        if (_snippet)
            dict[@"snippet"] = [self snippetWithWordStart: @"[" wordEnd: @"]"];
        if (_matches) {
            NSMutableArray* matches = [[NSMutableArray alloc] init];
            for (NSUInteger i = 0; i < _matches.count; ++i) {
                NSRange r = [self textRangeOfMatch: i];
                [matches addObject: @{@"term": @([self termIndexOfMatch: i]),
                                      @"range": @[@(r.location), @(r.length)]}];
            }
            dict[@"matches"] = matches;
        }
    }
    return dict;
}


@end




// Determine the number of characters in a range of UTF-8 bytes. */
static NSUInteger utf8BytesToChars(const void* bytes, NSUInteger byteStart, NSUInteger byteEnd) {
    if (byteStart == byteEnd)
        return 0;
    NSString* prefix = [[NSString alloc] initWithBytesNoCopy: (UInt8*)bytes + byteStart
                                                      length: byteEnd - byteStart
                                                    encoding: NSUTF8StringEncoding
                                                freeWhenDone: NO];
    return prefix.length;
}
