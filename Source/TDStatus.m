//
//  TDStatus.m
//  TouchDB
//
//  Created by Jens Alfke on 4/6/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "TDStatus.h"


NSString* const TDHTTPErrorDomain = @"TDHTTP";


struct StatusMapEntry {
    TDStatus status;
    int httpStatus;
    const char* message;
};

static const struct StatusMapEntry kStatusMap[] = {
    {kTDStatusNotFound,             404, "not_found"},           // for compatibility with CouchDB
    {kTDStatusDuplicate,            412, "Already exists"},      // really 'Precondition Failed'

    {kTDStatusBadEncoding,          400, "Bad data encoding"},
    {kTDStatusBadAttachment,        400, "Invalid attachment"},
    {kTDStatusAttachmentNotFound,   404, "Attachment not found"},
    {kTDStatusBadJSON,              400, "Invalid JSON"},
    {kTDStatusBadID,                400, "Invalid database/document/revision ID"},
    {kTDStatusBadParam,             400, "Invalid parameter in JSON body"},
    {kTDStatusDeleted,              404, "deleted"},

    {kTDStatusUpstreamError,        502, "Invalid response from remote replication server"},
    {kTDStatusDBError,              500, "Database error!"},
    {kTDStatusCorruptError,         500, "Invalid data in database"},
    {kTDStatusAttachmentError,      500, "Attachment store error"},
    {kTDStatusCallbackError,        500, "Application callback block failed"},
    {kTDStatusException,            500, "Internal error"},
};


int TDStatusToHTTPStatus( TDStatus status, NSString** outMessage ) {
    for (unsigned i=0; i < sizeof(kStatusMap)/sizeof(kStatusMap[0]); ++i) {
        if (kStatusMap[i].status == status) {
            if (outMessage)
                *outMessage = [NSString stringWithUTF8String: kStatusMap[i].message];
            return kStatusMap[i].httpStatus;
        }
    }
    if (outMessage)
        *outMessage = [NSHTTPURLResponse localizedStringForStatusCode: status];
    return status;
}


NSError* TDStatusToNSError( TDStatus status, NSURL* url ) {
    NSString* reason;
    status = TDStatusToHTTPStatus(status, &reason);
    NSDictionary* info = $dict({NSURLErrorKey, url},
                               {NSLocalizedFailureReasonErrorKey, reason},
                               {NSLocalizedDescriptionKey, $sprintf(@"%i %@", status, reason)});
    return [NSError errorWithDomain: TDHTTPErrorDomain code: status userInfo: info];
}
