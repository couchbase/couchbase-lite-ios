//
//  DictionaryObject.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

protocol DictionaryProtocol: ReadOnlyDictionaryProtocol, DictionaryFragment {
    @discardableResult func setDictionary(_ dictionary: Dictionary<String, Any>?) -> Self
    
    @discardableResult func set(_ value: Any?, forKey key: String) -> Self
    
    /* override */ func getArray(_ key: String) -> ArrayObject?
    
    /* override */ func getDictionary(_ key: String) -> DictionaryObject?
}

public class DictionaryObject: ReadOnlyDictionaryObject, DictionaryProtocol {
    public init() {
        super.init(CBLDictionary())
    }
    
    
    public init(dictionary: Dictionary<String, Any>?) {
        super.init(CBLDictionary())
        setDictionary(dictionary)
    }
    
    
    @discardableResult public func setDictionary(_ dictionary: Dictionary<String, Any>?) -> Self {
        dictImpl.setDictionary(DataConverter.convertSETDictionary(dictionary))
        return self
    }
    
    
    @discardableResult public func set(_ value: Any?, forKey key: String) -> Self {
        dictImpl.setObject(DataConverter.convertSETValue(value), forKey: key)
        return self
    }
    
    
    public override func getArray(_ key: String) -> ArrayObject? {
        return self.getValue(key) as? ArrayObject
    }
    
    
    public override func getDictionary(_ key: String) -> DictionaryObject? {
        return self.getValue(key) as? DictionaryObject
    }
    
    
    // MARK: DictionaryFragment
    
    
    public override subscript(key: String) -> Fragment {
        return Fragment(dictImpl[key])
    }
    
    
    // MARK: Internal
    
    
    init(_ impl: CBLDictionary) {
        super.init(impl)
    }
    
    
    // MARK: Private
    
    
    private var dictImpl: CBLDictionary {
        return _impl as! CBLDictionary
    }
}
