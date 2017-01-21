//
//  CBLMisc.h
//  CouchbaseLite
//
//  Source: https://github.com/couchbase/couchbase-lite-ios/blob/master/Source/CBLMisc.h
//  Created by Jens Alfke on 1/13/12.
//
//  Created by Pasin Suriyentrakorn on 1/4/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif
    
NS_ASSUME_NONNULL_BEGIN

/** Generates UUID. */
NSString* __nullable CBLCreateUUID( void );

/** Writes a hex dump of the bytes to the output string.
 Returns a pointer to the end of the string (where it writes a null.) */
char* CBLAppendHex( char *dst, const void* bytes, size_t length);

/** Generates a hex dump of a sequence of bytes.
 The result is lowercase. This is important for CouchDB compatibility. */
NSString* CBLHexFromBytes( const void* bytes, size_t length);
    
/** Returns YES if this error appears to be due to a creating a file/dir that already exists. */
BOOL CBLIsFileExistsError( NSError* error );

NS_ASSUME_NONNULL_END

#ifdef __cplusplus
}
#endif
