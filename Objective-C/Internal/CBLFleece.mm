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
#import "MCollection.hh"
#import "MDictIterator.hh"
#import "c4Document+Fleece.h"


@implementation NSObject (CBLFleece)
- (fleeceapi::MCollection<id>*) fl_collection {
    return nullptr;
}
@end


namespace cbl {
    DocContext::DocContext(CBLDatabase *db, CBLC4Document *doc)
    :fleeceapi::MContext({}, db.sharedKeys)
    ,_db(db)
    ,_doc(doc)
    ,_fleeceToNSStrings(FLCreateSharedStringsTable())
    { }


    id DocContext::toObject(fleeceapi::Value value) {
        return value.asNSObject(sharedKeys(), _fleeceToNSStrings);
    }
}


namespace fleeceapi {
    using namespace cbl;


    // Instantiate an Objective-C object for a Fleece dictionary with an "@type" key. */
    static id createSpecialObjectOfType(slice type, Dict properties, DocContext *context) {
        if (type == C4STR(kC4ObjectType_Blob)) {
            return [[CBLBlob alloc] initWithDatabase: context->database()
                                          properties: context->toObject(properties)];
        }
        return nil;
    }


    // These are the three MValue methods that have to be implemented in any specialization,
    // here specialized for <id>.

    template<>
    id MValue<id>::toNative(MValue *mv, MCollection<id> *parent, bool &cacheIt) {
        Value value = mv->value();
        switch (value.type()) {
            case kFLArray: {
                cacheIt = true;
                Class c = parent->mutableChildren() ? [CBLMutableArray class] : [CBLArray class];
                return [[c alloc] initWithMValue: mv inParent: parent];
            }
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
                Class c = parent->mutableChildren() ? [CBLMutableDictionary class]
                                                    : [CBLDictionary class];
                return [[c alloc] initWithMValue: mv inParent: parent];
            }
            default: {
                return ((DocContext*)parent->context())->toObject(value);
            }
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

    template<>
    id MDictIterator<id>::nativeKey() const {
        if (_iteratingMap) {
            return key().asNSString();
        } else {
            auto sharedStrings = ((DocContext*)_dict.context())->fleeceToNSStrings();
            return _dictIter.keyAsNSString(sharedStrings);
        }
    }


}


namespace cbl {
    using namespace fleeceapi;

    bool valueWouldChange(id newValue, const MValue<id> &oldValue, MCollection<id> &container) {
        // As a simplification we assume that array and dict values are always different, to avoid
        // a possibly expensive comparison.
        auto oldType = oldValue.value().type();
        if (oldType == kFLUndefined || oldType == kFLDict || oldType == kFLArray)
            return true;
        else if ([newValue isKindOfClass: [CBLArray class]]
                || [newValue isKindOfClass: [CBLArray class]])
            return true;
        else
            return ![newValue isEqual: oldValue.asNative(&container)];
    }


    bool asBool(const MValue<id> &val, const MCollection<id> &container) {
        if (val.value())
            return val.value().asBool();
        else
            return asBool(val.asNative(&container));
    }


    NSInteger asInteger(const MValue<id> &val, const MCollection<id> &container) {
        if (val.value())
            return (NSInteger)val.value().asInt();
        else
            return asInteger(val.asNative(&container));
    }


    long long asLongLong(const MValue<id> &val, const MCollection<id> &container) {
        if (val.value())
            return val.value().asInt();
        else
            return asLongLong(val.asNative(&container));
    }


    float asFloat(const MValue<id> &val, const MCollection<id> &container) {
        if (val.value())
            return val.value().asFloat();
        else
            return asFloat(val.asNative(&container));
    }


    double asDouble(const MValue<id> &val, const MCollection<id> &container) {
        if (val.value())
            return val.value().asDouble();
        else
            return asDouble(val.asNative(&container));
    }

}
