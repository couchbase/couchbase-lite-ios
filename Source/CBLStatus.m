//
//  CBLStatus.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 4/6/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
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
    // For compatibility with CouchDB, return the same strings it does (see couch_httpd.erl)
    {kCBLStatusBadRequest,           400, "bad_request"},
    {kCBLStatusUnauthorized,         401, "unauthorized"},
    {kCBLStatusNotFound,             404, "not_found"},
    {kCBLStatusForbidden,            403, "forbidden"},
    {kCBLStatusMethodNotAllowed,     405, "method_not_allowed"},
    {kCBLStatusNotAcceptable,        406, "not_acceptable"},
    {kCBLStatusConflict,             409, "conflict"},
    {kCBLStatusDuplicate,            412, "file_exists"},      // really 'Precondition Failed'
    {kCBLStatusUnsupportedType,      415, "bad_content_type"},

    // These are nonstandard status codes; map them to closest HTTP equivalents:
    {kCBLStatusBadEncoding,          400, "Bad data encoding"},
    {kCBLStatusBadAttachment,        400, "Invalid attachment"},
    {kCBLStatusAttachmentNotFound,   404, "Attachment not found"},
    {kCBLStatusBadJSON,              400, "Invalid JSON"},
    {kCBLStatusBadID,                400, "Invalid database/document/revision ID"},
    {kCBLStatusBadParam,             400, "Invalid parameter in HTTP query or JSON body"},
    {kCBLStatusDeleted,              404, "deleted"},
    {kCBLStatusInvalidStorageType,   406, "Can't open database in that storage format"},

    {kCBLStatusUpstreamError,        502, "Invalid response from remote replication server"},
    {kCBLStatusBadChangesFeed,       502, "Server changes feed parse error"},
    {kCBLStatusChangesFeedTruncated, 502, "Server changes feed truncated"},
    {kCBLStatusDBError,              500, "Database error!"},
    {kCBLStatusCorruptError,         500, "Invalid data in database"},
    {kCBLStatusAttachmentError,      500, "Attachment store error"},
    {kCBLStatusCallbackError,        500, "Application callback block failed"},
    {kCBLStatusException,            500, "Internal error"},
    {kCBLStatusDBBusy,               500, "Database locked"},
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


NSError* CBLStatusToNSErrorWithInfo( CBLStatus status, NSString *reason, NSURL* url,
                                     NSDictionary* extraInfo ) {
    NSString* statusMessage;
    status = CBLStatusToHTTPStatus(status, &statusMessage);
    reason = reason != nil ? reason : statusMessage;
    NSMutableDictionary* info = $mdict({NSURLErrorFailingURLErrorKey, url},
                                       {NSLocalizedFailureReasonErrorKey, reason},
                                       {NSLocalizedDescriptionKey, $sprintf(@"%i %@", status, reason)});
    if (extraInfo)
        [info addEntriesFromDictionary: extraInfo];
    return [NSError errorWithDomain: CBLHTTPErrorDomain code: status userInfo: info];
}


NSError* CBLStatusToNSError( CBLStatus status ) {
    return CBLStatusToNSErrorWithInfo(status, nil, nil, nil);
}


BOOL CBLStatusToOutNSError(CBLStatus status, NSError** outError) {
    if (outError)
        *outError = status < 300 ? nil : CBLStatusToNSError(status);
    return !CBLStatusIsError(status);
}


CBLStatus CBLStatusFromNSError(NSError* error, CBLStatus defaultStatus) {
    NSInteger code = error.code;
    if (!error)
        return kCBLStatusOK;
    else if ($equal(error.domain, CBLHTTPErrorDomain))
        return (CBLStatus)code;
    else
        return defaultStatus;
}
