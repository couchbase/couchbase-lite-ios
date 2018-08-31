//
//  CBLFleece.mm
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "CBLFleece.hh"
#import "CBLData.h"
#import "CBLDatabase+Internal.h"
#import "CBLDocument+Internal.h"
#import "MCollection.hh"
#import "MDictIterator.hh"
#import "c4Document+Fleece.h"


@implementation NSObject (CBLFleece)
- (fleece::MCollection<id>*) fl_collection {
    return nullptr;
}
@end


namespace cbl {
    DocContext::DocContext(CBLDatabase *db, CBLC4Document *doc)
    :fleece::MContext(fleece::alloc_slice())
    ,_db(db)
    ,_doc(doc)
    ,_fleeceToNSStrings(FLCreateSharedStringsTable())
    { }


    id DocContext::toObject(fleece::Value value) {
        return value.asNSObject(_fleeceToNSStrings);
    }
}


namespace fleece {
    using namespace cbl;

    // Check whether the dictionary is the old attachment or not:
    static bool isOldAttachment(Dict properties, DocContext *context) {
        if (properties.get(C4STR("digest")) != nullptr &&
            properties.get(C4STR("revpos")) != nullptr &&
            properties.get(C4STR("stub")) != nullptr &&
            properties.get(C4STR("length")) != nullptr)
            return true;
        return false;
    }

    // Instantiate an Objective-C object for a Fleece dictionary with an "@type" key. */
    static id createSpecialObjectOfType(Dict properties, DocContext *context) {
        slice type = properties.get(C4STR(kC4ObjectTypeProperty)).asString();
        if ((type && type == C4STR(kC4ObjectType_Blob)) || isOldAttachment(properties, context)) {
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
                id obj = createSpecialObjectOfType(value.asDict(), context);
                if (obj)
                    return obj;
                
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
    using namespace fleece;

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
