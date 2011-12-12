//
//  TDContentStore.m
//  TouchDB
//
//  Created by Jens Alfke on 12/10/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "TDContentStore.h"

#define kFileExtension "content"


@implementation TDContentStore

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


+ (TDContentKey) keyForContents: (NSData*)contents {
    NSCParameterAssert(contents);
    TDContentKey key;
    CC_SHA1(contents.bytes, (CC_LONG)contents.length, key.bytes);
    return key;
}

+ (NSData*) keyDataForContents: (NSData*)contents {
    TDContentKey key = [self keyForContents: contents];
    return [NSData dataWithBytes: &key length: sizeof(key)];
}


- (NSString*) pathForKey: (TDContentKey)key {
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


+ (BOOL) getKey: (TDContentKey*)outKey forFilename: (NSString*)filename {
    if (filename.length != 2*sizeof(TDContentKey) + 1 + strlen(kFileExtension))
        return NO;
    if (![filename hasSuffix: @"."kFileExtension])
        return NO;
    if (outKey) {
        uint8_t* dst = &outKey->bytes[0];
        for (unsigned i=0; i<sizeof(TDContentKey); ++i) {
            unichar digit1 = [filename characterAtIndex: 2*i];
            unichar digit2 = [filename characterAtIndex: 2*i+1];
            if (!isxdigit(digit1) || !isxdigit(digit2))
                return NO;
            *dst++ = 16*digittoint(digit1) + digittoint(digit2);
        }
    }
    return YES;
}


- (NSData*) contentsForKey: (TDContentKey)key {
    NSString* path = [self pathForKey: key];
    return [NSData dataWithContentsOfFile: path options: NSDataReadingMappedIfSafe error: nil];
}

- (BOOL) storeContents: (NSData*)contents
           creatingKey: (TDContentKey*)outKey
{
    *outKey = [[self class] keyForContents: contents];
    NSString* path = [self pathForKey: *outKey];
    if ([[NSFileManager defaultManager] isReadableFileAtPath: path])
        return YES;
    NSError* error;
    if (![contents writeToFile: path options: NSDataWritingAtomic error: &error]) {
        Warn(@"TDContentStore: Couldn't write to %@: %@", path, error);
        return NO;
    }
    return YES;
}

- (NSArray*) allKeys {
    NSArray* contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath: _path
                                                                            error: nil];
    if (!contents)
        return nil;
    return [contents my_map: ^(id filename) {
        TDContentKey key;
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


- (NSUInteger) deleteContentsExceptWithKeys: (NSSet*)keysToKeep {
    NSFileManager* fmgr = [NSFileManager defaultManager];
    NSArray* contents = [fmgr contentsOfDirectoryAtPath: _path error: nil];
    if (!contents)
        return 0;
    NSUInteger numDeleted = 0;
    NSMutableData* curKeyData = [NSMutableData dataWithLength: sizeof(TDContentKey)];
    for (NSString* filename in contents) {
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
