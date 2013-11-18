//
//  LoggingMode.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 9/24/13.
//
//

typedef enum {
    kLoggingToNowhere,
    kLoggingToTTY,
    kLoggingToColorTTY,
    kLoggingToColorXcode,
    kLoggingToFile,
    kLoggingToOther
} LoggingTo;


LoggingTo GetLoggingMode(void);
