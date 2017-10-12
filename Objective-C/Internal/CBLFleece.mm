//
//  CBLFleece.mm
//  CouchbaseLite
//
//  Created by Jens Alfke on 10/11/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLFleece.hh"
#import "CBLData.h"
#import "CBLDatabase+Internal.h"
#import "CBLDocument+Internal.h"
#import "CBLSharedKeys.hh"
#import "MCollection.hh"
#import "c4Document+Fleece.h"


DocContext::DocContext(CBLDatabase *db, CBLC4Document *doc)
:fleeceapi::MContext({}, db.sharedKeys)
,_db(db)
,_doc(doc)
{ }


namespace fleeceapi {


    // Instantiate an Objective-C object for a Fleece dictionary with an "@type" key. */
    static id createSpecialObjectOfType(slice type, Dict properties, DocContext *context) {
        if (type == C4STR(kC4ObjectType_Blob)) {
            return [[CBLBlob alloc] initWithDatabase: context->database()
                                          properties: properties.asNSObject(context->sharedKeys())];
        }
        return nil;
    }


    // These are the three MValue methods that have to be implemented in any specialization,
    // here specialized for <id>.

    template<>
    id MValue<id>::toNative(MValue *mv, MCollection<id> *parent, bool &cacheIt) {
        Value value = mv->value();
        switch (value.type()) {
            case kFLArray:
                cacheIt = true;
                return [[CBLArray alloc] initWithMValue: mv inParent: parent];
            case kFLDict: {
                cacheIt = true;
                auto context = (DocContext*)parent->context();
                auto sk = context->sharedKeys();
                slice type = value.asDict().get(C4STR(kC4ObjectTypeProperty), sk).asString();
                if (type) {
                    id obj = createSpecialObjectOfType(type, value.asDict(), context);
                    if (obj)
                        return obj;
                }
                return [[CBLDictionary alloc] initWithMValue: mv inParent: parent];
            }
            default:
                return value.asNSObject(parent->context()->sharedKeys());
        }
    }

    template<>
    MCollection<id>* MValue<id>::collectionFromNative(id native) {
        return [native fl_collection];
    }

    template<>
    void MValue<id>::encodeNative(Encoder &enc, id obj) {
        enc << obj;
    }

}

using namespace fleeceapi;


bool valueWouldChange(id newValue, const MValue<id> &oldValue, MCollection<id> &container) {
    // As a simplification we assume that array and dict values are always different, to avoid
    // a possibly expensive comparison.
    auto oldType = oldValue.value().type();
    if (oldType == kFLUndefined || oldType == kFLDict || oldType == kFLArray)
        return true;
    else if ([newValue isKindOfClass: [CBLReadOnlyArray class]]
            || [newValue isKindOfClass: [CBLReadOnlyArray class]])
        return true;
    else
        return ![newValue isEqual: oldValue.asNative(&container)];
}


@implementation NSObject (CBLFleece)
- (fleeceapi::MCollection<id>*) fl_collection {
    return nullptr;
}
@end


bool asBool(const MValue<id> &val, const MCollection<id> &container) {
    if (val.value())
        return val.value().asBool();
    else
        return [CBLData booleanValueForObject: val.asNative(&container)];
}


NSInteger asInteger(const MValue<id> &val, const MCollection<id> &container) {
    if (val.value())
        return val.value().asInt();
    else
        return [$castIf(NSNumber, val.asNative(&container)) integerValue];
}


long long asLongLong(const MValue<id> &val, const MCollection<id> &container) {
    if (val.value())
        return val.value().asInt();
    else
        return [$castIf(NSNumber, val.asNative(&container)) longLongValue];
}


float asFloat(const MValue<id> &val, const MCollection<id> &container) {
    if (val.value())
        return val.value().asFloat();
    else
        return [$castIf(NSNumber, val.asNative(&container)) floatValue];
}


double asDouble(const MValue<id> &val, const MCollection<id> &container) {
    if (val.value())
        return val.value().asDouble();
    else
        return [$castIf(NSNumber, val.asNative(&container)) doubleValue];
}
