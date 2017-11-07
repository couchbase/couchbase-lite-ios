//
//  MutableFragment.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


/// MutableFragmentProtocol provides read and write access to the data value
/// wrapped by a fragment object.
protocol MutableFragmentProtocol: FragmentProtocol {
    
    var value: Any? { get set }
    
    var array: MutableArrayObject? { get }
    
    var dictionary: MutableDictionaryObject? { get }
    
}


/// MutableArrayFragment protocol provides subscript access to Fragment objects
/// by index.
protocol MutableArrayFragment {
    subscript(index: Int) -> MutableFragment { get }
}


/// MutableDictionaryFragment protocol provides subscript access to
/// CBLMutableFragment objects by key.
protocol MutableDictionaryFragment {
    subscript(key: String) -> MutableFragment { get }
}


/// MutableFragment provides read and write access to data value. MutableFragment also provides
/// subscript access by either key or index to the nested values which are wrapped by
/// MutableFragment objects.
public class MutableFragment: Fragment, MutableDictionaryFragment, MutableArrayFragment {
    
    /// Gets the value from or sets the value to the fragment object. The object types are
    /// ArrayObject, Blob, DictionaryObject, Number, String, NSNull, or nil
    public override var value: Any? {
        set {
            fragmentImpl.value = (DataConverter.convertSETValue(newValue) as! NSObject)
        }
        
        get {
            return DataConverter.convertGETValue(fragmentImpl.value)
        }
    }
    
    
    /// Get the value as an MutableArrayObject object, a mapping object of an array value.
    /// Returns nil if the value is nil, or the value is not an array.
    public override var array: MutableArrayObject? {
        return DataConverter.convertGETValue(fragmentImpl.array) as? MutableArrayObject
    }
    
    
    /// Get a property's value as a MutableDictionaryObject object, a mapping object of
    /// a dictionary value. Returns nil if the value is nil, or the value is not a dictionary.
    public override var dictionary: MutableDictionaryObject? {
        return DataConverter.convertGETValue(fragmentImpl.dictionary) as? MutableDictionaryObject
    }
    
    
    // MARK: Subscripts
    
    
    /// Subscript access to a MutableFragment object by index.
    ///
    /// - Parameter index: The index.
    public override subscript(index: Int) -> MutableFragment {
        return MutableFragment(fragmentImpl[UInt(index)])
    }
    
    
    /// Subscript access to a MutableFragment object by key.
    ///
    /// - Parameter key: The key.
    public override subscript(key: String) -> MutableFragment {
        return MutableFragment(fragmentImpl[key])
    }
    
    
    // MARK: Internal
    
    
    init(_ impl: CBLMutableFragment?) {
        super.init(impl ?? MutableFragment.kNonexistent)
    }
    
    
    // MARK: Private
    
    
    private var fragmentImpl: CBLMutableFragment {
        return _impl as! CBLMutableFragment
    }


    static let kNonexistent = CBLMutableFragment()

}
