//
//  CBLLog+Admin.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/18/18.
//  Copyright © 2018 Couchbase. All rights reserved.
//

#import "CBLLog.h"
#import "CBLDatabase.h"


#ifdef __cplusplus
extern "C" {
#endif

NS_ASSUME_NONNULL_BEGIN

// Must be called at startup to register the logging callback. It also sets up log domain levels
// based on user defaults named:
//   CBLLogLevel       Sets the default level for all domains; normally Warning
//   CBLLog            Sets the level for the default domain
//   CBLLog___         Sets the level for the '___' domain
// The level values can be Verbose or V or 2 for verbose level,
// or Debug or D or 3 for Debug level,
// or NO or false or 0 to disable entirely;
// any other value, such as YES or Y or 1, sets Info level.
//
// Also, setting the user default CBLBreakOnWarning to YES/true will cause a breakpoint after any
// warning is logged.
void CBLLog_Init(void);


void CBLLog_SetLevel(CBLLogDomain domain, CBLLogLevel level);


NS_ASSUME_NONNULL_END

#ifdef __cplusplus
}
#endif
