//
//  TDStatus.h
//  TouchDB
//
//  Created by Jens Alfke on 4/5/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//


/** TouchDB internal status/error codes. Superset of HTTP status codes. */
typedef enum {
    kTDStatusOK             = 200,
    kTDStatusCreated        = 201,
    kTDStatusAccepted       = 206,
    
    kTDStatusNotModified    = 304,
    
    kTDStatusBadRequest     = 400,
    kTDStatusForbidden      = 403,
    kTDStatusNotFound       = 404,
    kTDStatusNotAcceptable  = 406,
    kTDStatusConflict       = 409,
    kTDStatusDuplicate      = 412,      // Formally known as "Precondition Failed"
    kTDStatusUnsupportedType= 415,
    
    kTDStatusServerError    = 500,
    kTDStatusUpstreamError  = 502,      // aka Bad Gateway -- upstream server error
    
    // Non-HTTP errors:
    kTDStatusBadEncoding    = 490,
    kTDStatusBadAttachment  = 491,
    kTDStatusAttachmentNotFound = 492,
    kTDStatusBadJSON        = 493,
    kTDStatusBadID          = 494,
    kTDStatusBadParam       = 495,
    
    kTDStatusDBError        = 590,      // SQLite error
    kTDStatusCorruptError   = 591,      // bad data in database
    kTDStatusAttachmentError= 592,      // problem with attachment store
    kTDStatusCallbackError  = 593,      // app callback (emit fn, etc.) failed
    kTDStatusException      = 594,      // Exception raised/caught
} TDStatus;


static inline bool TDStatusIsError(TDStatus status) {return status >= 300;}

int TDStatusToHTTPStatus( TDStatus status, NSString** outMessage );

NSError* TDStatusToNSError( TDStatus status, NSURL* url );
