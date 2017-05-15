//
//  Fragment.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

/// FragmentProtocol provides read and write access to the data value wrapped by
/// a fragment object.
protocol FragmentProtocol: ReadOnlyFragmentProtocol {
    var value: Any? { get set }
    
    var array: ArrayObject? { get }
    
    var dictionary: DictionaryObject? { get }
}


/// ArrayFragment protocol provides subscript access to Fragment objects by index.
protocol ArrayFragment {
    subscript(index: Int) -> Fragment { get }
}


/// CBLDictionaryFragment protocol provides subscript access to CBLFragment objects by key.
protocol DictionaryFragment {
    subscript(key: String) -> Fragment { get }
}


/// Fragment provides read and write access to data value. Fragment also provides
/// subscript access by either key or index to the nested values which are wrapped by 
/// Fragment objects.
public class Fragment: ReadOnlyFragment, DictionaryFragment, ArrayFragment {
    /// Gets the value from or sets the value to the fragment object. The object types are 
    /// ArrayObject, Blob, DictionaryObject, Number, String, NSNull, or nil.
    public override var value: Any? {
        set {
            fragmentImpl.value = (DataConverter.convertSETValue(newValue) as! NSObject)
        }
        
        get {
            return DataConverter.convertGETValue(fragmentImpl.value)
        }
    }
    
    
    /// Get the value as an ArrayObject object, a mapping object of an array value.
    /// Returns nil if the value is nil, or the value is not an array.
    public override var array: ArrayObject? {
        return DataConverter.convertGETValue(fragmentImpl.array) as? ArrayObject
    }
    
    
    /// Get a property's value as a DictionaryObject object, a mapping object of 
    /// a dictionary value. Returns nil if the value is nil, or the value is not a dictionary.
    public override var dictionary: DictionaryObject? {
        return DataConverter.convertGETValue(fragmentImpl.dictionary) as? DictionaryObject
    }
    
    
    // MARK: ArrayFragment
    
    
    /// Subscript access to a CBLFragment object by index.
    /// - Parameter index: the index.
    /// - Returns: the CBLFragment object.
    public override subscript(index: Int) -> Fragment {
        return Fragment(fragmentImpl[UInt(index)])
    }
    
    
    // MARK: DictionaryFragment
    
    
    /// Subscript access to a CBLFragment object by key.
    /// - Parameter key: the key.
    /// - Returns: the CBLFragment object.
    public override subscript(key: String) -> Fragment {
        return Fragment(fragmentImpl[key])
    }
    
    
    // MARK: Internal
    
    
    init(_ impl: CBLFragment) {
        super.init(impl)
    }
    
    
    // MARK: Private
    
    
    private var fragmentImpl: CBLFragment {
        return _impl as! CBLFragment
    }
}
