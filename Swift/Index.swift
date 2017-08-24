//
//  Index.swift
//  CBL Swift
//
//  Created by Pasin Suriyentrakorn on 8/23/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


/// Index represents an index which could be a value index for regular queries or
/// full-text search (FTS) index for full-text queries (using the match operator).
public class Index {
    
    /// Creates an ON operator used for specifying the items or properties to be indexed
    /// in order to create a value index.
    ///
    /// - Returns: The ON operator.
    public class func valueIndex() -> ValueIndexOn {
        return ValueIndexOn();
    }
    
    
    /// Creates an ON operator used for specifying an item or a property to be indexed
    /// in order to create a full-text search index.
    ///
    /// - Returns: The ON operator.
    public class func ftsIndex() -> FTSIndexOn {
        return FTSIndexOn();
    }
    
    // MARK: Internal
    
    var impl: CBLIndex
    
    init(impl: CBLIndex) {
        self.impl = impl
    }
    
}


// MARK: Value Index


/// An ON operator for creating a value index.
public class ValueIndexOn {
    
    /// Creates a value index with the given index items. The index items are a list of
    /// the properties or expressions to be indexed.
    ///
    /// - Parameter items: The index items.
    /// - Returns: The value index.
    public func on(_ items: ValueIndexItem...) -> ValueIndex {
        return ValueIndex(items: items)
    }
    
}


/// A value index for regular queries.
public class ValueIndex: Index {
    
    // MARK: Internal
    
    init(items: [ValueIndexItem]) {
        var cblItems: [CBLValueIndexItem] = []
        for item in items {
            cblItems.append(item.impl)
        }
        super.init(impl: CBLIndex.valueIndex(on: cblItems))
    }
    
}


/// Value Index Item.
public class ValueIndexItem {
    
    ///  Creates a value index item with the given expression.
    ///
    /// - Parameter expression: The expression to index. Typically a property expression.
    /// - Returns: The value index item.
    public class func expression(_ expression: Expression) -> ValueIndexItem {
        return ValueIndexItem(impl: CBLValueIndexItem.expression(expression.impl))
    }
    
    // MARK: Internal
    
    let impl: CBLValueIndexItem
    
    init(impl: CBLValueIndexItem) {
        self.impl = impl
    }
    
}


// MARK: FTS Index

/// An ON operator for creating a full-text search index.
public class FTSIndexOn {
    
    /// Creates a full-text search index with the given index item. The index item is the property
    /// be indexed.
    ///
    /// - Parameter item: The index item.
    /// - Returns: The full-text search index.
    public func on(_ item: FTSIndexItem) -> FTSIndex {
        return FTSIndex(item: item, ignoreAccents: nil, locale: nil)
    }
    
}


/// A full-text search index for full-text search query with the match operator.
public class FTSIndex: Index {
    
    /// Set to true ignore accents/diacritical marks. The default value is false.
    ///
    /// - Parameter ignoreAccents: The ignore accent value.
    /// - Returns: The FTSIndex instance.
    public func ignoreAccents(_ ignoreAccents: Bool) -> Self {
        if ignoreAccents != self.ignoreAccents {
            self.ignoreAccents = ignoreAccents
            self.impl = CBLIndex.ftsIndex(on: item.impl, options: self.options())
        }
        return self
    }
    
    
    /// The locale code which is an ISO-639 language code plus, optionally, an underscore
    /// and an ISO-3166 country code: "en", "en_US", "fr_CA", etc. Setting the locale code affects
    /// how word breaks and word stems are parsed. Setting nil value to use current locale and
    /// setting "" to disable stemming. The default value is nil.
    ///
    /// - Parameter locale: The locale code.
    /// - Returns: The FTSIndex instance.
    public func locale(_ locale: String?) -> Self {
        if locale != self.locale {
            self.locale = locale
            self.impl = CBLIndex.ftsIndex(on: item.impl, options: self.options())
        }
        return self
    }
    
    // MARK: Internal
    
    let item: FTSIndexItem
    var ignoreAccents: Bool?
    var locale: String?
    
    init(item: FTSIndexItem, ignoreAccents: Bool?, locale: String?) {
        self.item = item
        self.ignoreAccents = ignoreAccents
        self.locale = locale
        super.init(impl: CBLIndex.ftsIndex(on: item.impl, options: self.options()))
    }
    
    func options() -> CBLFTSIndexOptions? {
        let options = CBLFTSIndexOptions()
        options.ignoreAccents = ignoreAccents ?? false
        options.locale = locale
        return options
    }

}


/// Full-text search index item.
public class FTSIndexItem {
    
    /// Creates a full-text search index item with the given expression.
    ///
    /// - Parameter expression: The expression to index. Typically a property expression used to
    ///                         perform the match operation against with.
    /// - Returns: The full-text index item.
    public class func expression(_ expression: Expression) -> FTSIndexItem {
        return FTSIndexItem(impl: CBLFTSIndexItem.expression(expression.impl))
    }
    
    // MARK: Internal
    
    let impl: CBLFTSIndexItem
    
    init(impl: CBLFTSIndexItem) {
        self.impl = impl
    }
    
}
