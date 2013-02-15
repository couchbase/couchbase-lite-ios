//
//  CBLStatus.m
//  CouchbaseLite
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

#import "CBLStatus.h"


NSString* const CBLHTTPErrorDomain = @"CBLHTTP";


struct StatusMapEntry {
    CBLStatus status;
    int httpStatus;
    const char* message;
};

static const struct StatusMapEntry kStatusMap[] = {
    {kCBLStatusNotFound,             404, "not_found"},           // for compatibility with CouchDB
    {kCBLStatusConflict,             409, "conflict"},
    {kCBLStatusDuplicate,            412, "Already exists"},      // really 'Precondition Failed'

    {kCBLStatusBadEncoding,          400, "Bad data encoding"},
    {kCBLStatusBadAttachment,        400, "Invalid attachment"},
    {kCBLStatusAttachmentNotFound,   404, "Attachment not found"},
    {kCBLStatusBadJSON,              400, "Invalid JSON"},
    {kCBLStatusBadID,                400, "Invalid database/document/revision ID"},
    {kCBLStatusBadParam,             400, "Invalid parameter in JSON body"},
    {kCBLStatusDeleted,              404, "deleted"},

    {kCBLStatusUpstreamError,        502, "Invalid response from remote replication server"},
    {kCBLStatusDBError,              500, "Database error!"},
    {kCBLStatusCorruptError,         500, "Invalid data in database"},
    {kCBLStatusAttachmentError,      500, "Attachment store error"},
    {kCBLStatusCallbackError,        500, "Application callback block failed"},
    {kCBLStatusException,            500, "Internal error"},
};


int CBLStatusToHTTPStatus( CBLStatus status, NSString** outMessage ) {
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


NSError* CBLStatusToNSError( CBLStatus status, NSURL* url ) {
    NSString* reason;
    status = CBLStatusToHTTPStatus(status, &reason);
    NSDictionary* info = $dict({NSURLErrorKey, url},
                               {NSLocalizedFailureReasonErrorKey, reason},
                               {NSLocalizedDescriptionKey, $sprintf(@"%i %@", status, reason)});
    return [NSError errorWithDomain: CBLHTTPErrorDomain code: status userInfo: info];
}


CBLStatus CBLStatusFromNSError(NSError* error, CBLStatus defaultStatus) {
    if (!error)
        return kCBLStatusOK;
    if (!$equal(error.domain, CBLHTTPErrorDomain))
        return defaultStatus;
    return (CBLStatus)error.code;
}
