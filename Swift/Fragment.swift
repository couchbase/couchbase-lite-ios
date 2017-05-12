//
//  Fragment.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

protocol FragmentProtocol: ReadOnlyFragmentProtocol {
    var value: Any? { get set }
    
    var array: ArrayObject? { get }
    
    var dictionary: DictionaryObject? { get }
}


protocol DictionaryFragment {
    subscript(key: String) -> Fragment { get }
}


protocol ArrayFragment {
    subscript(index: Int) -> Fragment { get }
}


public class Fragment: ReadOnlyFragment, DictionaryFragment, ArrayFragment {
    public override var value: Any? {
        set {
            fragmentImpl.value = (DataConverter.convertSETValue(newValue) as! NSObject)
        }
        
        get {
            return DataConverter.convertGETValue(fragmentImpl.value)
        }
    }
    
    
    public override var array: ArrayObject? {
        return DataConverter.convertGETValue(fragmentImpl.array) as? ArrayObject
    }
    
    
    public override var dictionary: DictionaryObject? {
        return DataConverter.convertGETValue(fragmentImpl.dictionary) as? DictionaryObject
    }
    
    
    // MARK: DictionaryFragment
    
    
    public override subscript(key: String) -> Fragment {
        return Fragment(fragmentImpl[key])
    }
    
    
    // MARK: ArrayFragment
    
    
    public override subscript(index: Int) -> Fragment {
        return Fragment(fragmentImpl[UInt(index)])
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
