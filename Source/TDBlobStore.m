//
//  TDBlobStore.m
//  TouchDB
//
//  Created by Jens Alfke on 12/10/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "TDBlobStore.h"

#define kFileExtension "blob"


@implementation TDBlobStore

- (id) initWithPath: (NSString*)dir error: (NSError**)outError {
    Assert(dir);
    self = [super init];
    if (self) {
        _path = [dir copy];
        BOOL isDir;
        if (![[NSFileManager defaultManager] fileExistsAtPath: dir isDirectory: &isDir] || !isDir) {
            if (![[NSFileManager defaultManager] createDirectoryAtPath: dir
                                           withIntermediateDirectories: NO
                                                            attributes: nil
                                                                 error: outError]) {
                [self release];
                return nil;
            }
        }
    }
    return self;
}


- (void)dealloc {
    [_path release];
    [super dealloc];
}


+ (TDBlobKey) keyForBlob: (NSData*)blob {
    NSCParameterAssert(blob);
    TDBlobKey key;
    CC_SHA1(blob.bytes, (CC_LONG)blob.length, key.bytes);
    return key;
}

+ (NSData*) keyDataForBlob: (NSData*)blob {
    TDBlobKey key = [self keyForBlob: blob];
    return [NSData dataWithBytes: &key length: sizeof(key)];
}


- (NSString*) pathForKey: (TDBlobKey)key {
    char out[2*sizeof(key.bytes) + 1 + strlen(kFileExtension) + 1];
    char *dst = &out[0];
    for( size_t i=0; i<sizeof(key.bytes); i+=1 )
        dst += sprintf(dst,"%02X", key.bytes[i]);
    strcat(out, ".");
    strcat(out, kFileExtension);
    NSString* name =  [[NSString alloc] initWithCString: out encoding: NSASCIIStringEncoding];
    NSString* path = [_path stringByAppendingPathComponent: name];
    [name release];
    return path;
}


+ (BOOL) getKey: (TDBlobKey*)outKey forFilename: (NSString*)filename {
    if (filename.length != 2*sizeof(TDBlobKey) + 1 + strlen(kFileExtension))
        return NO;
    if (![filename hasSuffix: @"."kFileExtension])
        return NO;
    if (outKey) {
        uint8_t* dst = &outKey->bytes[0];
        for (unsigned i=0; i<sizeof(TDBlobKey); ++i) {
            unichar digit1 = [filename characterAtIndex: 2*i];
            unichar digit2 = [filename characterAtIndex: 2*i+1];
            if (!isxdigit(digit1) || !isxdigit(digit2))
                return NO;
            *dst++ = 16*digittoint(digit1) + digittoint(digit2);
        }
    }
    return YES;
}


- (NSData*) blobForKey: (TDBlobKey)key {
    NSString* path = [self pathForKey: key];
    return [NSData dataWithContentsOfFile: path options: NSDataReadingMappedIfSafe error: nil];
}

- (BOOL) storeBlob: (NSData*)blob
           creatingKey: (TDBlobKey*)outKey
{
    *outKey = [[self class] keyForBlob: blob];
    NSString* path = [self pathForKey: *outKey];
    if ([[NSFileManager defaultManager] isReadableFileAtPath: path])
        return YES;
    NSError* error;
    if (![blob writeToFile: path options: NSDataWritingAtomic error: &error]) {
        Warn(@"TDContentStore: Couldn't write to %@: %@", path, error);
        return NO;
    }
    return YES;
}

- (NSArray*) allKeys {
    NSArray* blob = [[NSFileManager defaultManager] contentsOfDirectoryAtPath: _path
                                                                            error: nil];
    if (!blob)
        return nil;
    return [blob my_map: ^(id filename) {
        TDBlobKey key;
        if ([[self class] getKey: &key forFilename: filename])
            return [NSData dataWithBytes: &key length: sizeof(key)];
        else
            return nil;
    }];
}


- (NSUInteger) count {
    NSUInteger n = 0;
    NSFileManager* fmgr = [NSFileManager defaultManager];
    for (NSString* filename in [fmgr contentsOfDirectoryAtPath: _path error: nil]) {
        if ([[self class] getKey: NULL forFilename: filename])
            ++n;
    }
    return n;
}


- (NSUInteger) deleteBlobsExceptWithKeys: (NSSet*)keysToKeep {
    NSFileManager* fmgr = [NSFileManager defaultManager];
    NSArray* blob = [fmgr contentsOfDirectoryAtPath: _path error: nil];
    if (!blob)
        return 0;
    NSUInteger numDeleted = 0;
    NSMutableData* curKeyData = [NSMutableData dataWithLength: sizeof(TDBlobKey)];
    for (NSString* filename in blob) {
        if ([[self class] getKey: curKeyData.mutableBytes forFilename: filename]) {
            if (![keysToKeep containsObject: curKeyData]) {
                NSError* error;
                if ([fmgr removeItemAtPath: [_path stringByAppendingPathComponent: filename]
                                 error: &error])
                    ++numDeleted;
                else
                    Warn(@"%@: Failed to delete '%@': %@", self, filename, error);
            }
        }
    }
    return numDeleted;
}


@end
