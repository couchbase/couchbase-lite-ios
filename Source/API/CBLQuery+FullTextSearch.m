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
{
    self = [super initWithDocID: docID sequence: sequence key: $null value: value docRevision: nil];
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
    id<CBL_QueryRowStorage> storage = self.storage;
    if (!storage)
        Warn(@"CBLFullTextQueryRow: cannot get the fullText, the database is gone");
    return [storage fullTextForDocument: self.documentID
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
    if (!rawText)
        return NSMakeRange(NSNotFound, 0);
    return NSMakeRange(utf8BytesToChars(rawText.bytes, 0, byteStart),
                       utf8BytesToChars(rawText.bytes, byteStart, byteStart + byteLength));
}


- (NSString*) snippetWithWordStart: (NSString*)wordStart
                           wordEnd: (NSString*)wordEnd
{
    if (_snippet) {
        NSMutableString* snippet = [_snippet mutableCopy];
        [snippet replaceOccurrencesOfString: @"\001" withString: wordStart
                                    options:NSLiteralSearch range:NSMakeRange(0, snippet.length)];
        [snippet replaceOccurrencesOfString: @"\002" withString: wordEnd
                                    options:NSLiteralSearch range:NSMakeRange(0, snippet.length)];
        return snippet;
    } else {
        // Generate the snippet myself. This is pretty crude compared to SQLite's algorithm,
        // which is described at http://sqlite.org/fts3.html#section_4_2
        NSString* fullText = self.fullText;
        if (!fullText)
            return @"";

        // Use an NSLinguisticTagger to tokenize the full text into a list of word char ranges:
        NSLinguisticTagger* tagger = [[NSLinguisticTagger alloc] initWithTagSchemes:@[NSLinguisticTagSchemeTokenType] options: 0];
        tagger.string = fullText;
        NSArray* tokenRanges = nil;
        [tagger tagsInRange: NSMakeRange(0, fullText.length)
                     scheme: NSLinguisticTagSchemeTokenType
                    options: NSLinguisticTaggerOmitPunctuation | NSLinguisticTaggerOmitWhitespace
                                | NSLinguisticTaggerOmitOther
                tokenRanges: &tokenRanges];
        if (!tokenRanges)
            return nil;

        // Find the indexes (in tokenRanges) of the first and last match:
        //FIX: It would be better to find a region that includes as many matches as possible.
        NSUInteger start = [self textRangeOfMatch: 0].location;
        NSUInteger end = NSMaxRange([self textRangeOfMatch: self.matchCount - 1]);
        NSInteger startTokenIndex = -1, endTokenIndex = -1;
        NSUInteger i = 0;
        for (NSValue* rangeObj in tokenRanges) {
            NSRange range = rangeObj.rangeValue;
            if (startTokenIndex < 0 && range.location >= start)
                startTokenIndex = i;
            endTokenIndex = i;
            if (NSMaxRange(range) >= end)
                break;
            i++;
        }

        // Try to get exactly the desired number of tokens in the snippet by adjusting start/end:
        static const NSInteger kMaxTokens = 15;
        NSInteger addTokens = kMaxTokens - (endTokenIndex-startTokenIndex+1);
        if (addTokens > 0) {
            startTokenIndex -= MIN(addTokens/2, startTokenIndex);
            endTokenIndex = MIN(startTokenIndex + kMaxTokens, (NSInteger)tokenRanges.count - 1);
            startTokenIndex = MAX(0, endTokenIndex - kMaxTokens);
        } else {
            endTokenIndex += addTokens;
        }

        if (startTokenIndex > 0)
            --startTokenIndex;      // start the snippet one word before the first match

        // Update the snippet character range to the ends of the tokens:
        NSString *prefix = @"", *suffix = @"";
        if (startTokenIndex > 0) {
            start = [tokenRanges[startTokenIndex] rangeValue].location;
            prefix = @"…";
        } else {
            start = 0;
        }
        if ((NSUInteger)endTokenIndex < tokenRanges.count - 1) {
            end = NSMaxRange([tokenRanges[endTokenIndex] rangeValue]);
            suffix = @"…";
        } else {
            end = fullText.length;
        }

        NSMutableString *snippet = [[fullText substringWithRange: NSMakeRange(start, end-start)]
                                        mutableCopy];

        // Wrap matches with caller-supplied strings:
        if (wordStart || wordEnd) {
            NSInteger delta = -start;
            for (NSUInteger i = 0; i < self.matchCount; i++) {
                NSRange range = [self textRangeOfMatch: i];
                if (range.location >= start && NSMaxRange(range) <= end) {
                    if (wordStart) {
                        [snippet insertString: wordStart atIndex: range.location + delta];
                        delta += wordStart.length;
                    }
                    if (wordEnd) {
                        [snippet insertString: wordEnd atIndex: NSMaxRange(range) + delta];
                        delta += wordEnd.length;
                    }
                }
            }
        }

        // Add ellipses at start/end if necessary:
        [snippet insertString: prefix atIndex: 0];
        [snippet appendString: suffix];
        return snippet;
    }
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
