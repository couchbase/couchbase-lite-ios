//
//  LoggingMode.c
//  CouchbaseLite
//
//  Created by Jens Alfke on 9/24/13.
//
//

#include "LoggingMode.h"
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/fcntl.h>
#include <sys/param.h>


/** Does the file descriptor connect to console output, i.e. a terminal or Xcode? */
LoggingTo GetLoggingMode(void)
{
    if( isatty(STDERR_FILENO) ) {
        const char *xcode_colors = getenv("XcodeColors");
        if (xcode_colors && (strcmp(xcode_colors, "YES") == 0))
            return kLoggingToColorXcode;

        const char *term = getenv("TERM");
        if( term && (strstr(term,"ANSI") || strstr(term,"ansi") || strstr(term,"color")) )
            return kLoggingToColorTTY;
        else
            return kLoggingToTTY;
    } else {
        char path[MAXPATHLEN];
        if( fcntl(STDERR_FILENO, F_GETPATH, path) != 0 )
            return kLoggingToOther;
        if (strcmp(path, "/dev/null") == 0)
            return kLoggingToNowhere;
        else
            return kLoggingToFile;
    }
}


