//
//  Index.swift
//  CBL Swift
//
//  Created by Pasin Suriyentrakorn on 8/23/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


/// Index represents an index which could be a value index for regular queries or
/// full-text index for full-text queries (using the match operator).
public class Index {
    
    /// Create a value index with the given index items. The index items are a list of
    /// the properties or expressions to be indexed.
    
    /// - Parameter: items The index items.
    /// - Returns: The ValueIndex.
    public class func valueIndex(withItems items: ValueIndexItem...) -> ValueIndex {
        return ValueIndex(items: items)
    }
    
    
    /// Create a full-text index with the given index items. Typically
    /// the index items are the properties that are used to perform the
    /// match operation against with.
    ///
    /// - Parameter: items The index items.
    /// - Returns: The ON operator.
    public class func fullTextIndex(withItems items: FullTextIndexItem...) -> FullTextIndex {
        return FullTextIndex(items: items, ignoreAccents: nil, locale: nil)
    }
    
    // MARK: Internal
    
    var impl: CBLIndex
    
    init(impl: CBLIndex) {
        self.impl = impl
    }
    
}


// MARK: Value Index


/// A value index for regular queries.
public class ValueIndex: Index {
    
    // MARK: Internal
    
    init(items: [ValueIndexItem]) {
        var cblItems: [CBLValueIndexItem] = []
        for item in items {
            cblItems.append(item.impl)
        }
        super.init(impl: CBLIndex.valueIndex(with: cblItems))
    }
    
}


/// Value Index Item.
public class ValueIndexItem {
    
    public class func property(_ property: String) -> ValueIndexItem {
        return ValueIndexItem(impl: CBLValueIndexItem.property(property))
    }
    
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


/// A full-text search index for full-text search query with the match operator.
public class FullTextIndex: Index {
    
    /// Set to true ignore accents/diacritical marks. The default value is false.
    ///
    /// - Parameter ignoreAccents: The ignore accent value.
    /// - Returns: The FTSIndex instance.
    public func ignoreAccents(_ ignoreAccents: Bool) -> Self {
        if ignoreAccents != self.ignoreAccents {
            self.ignoreAccents = ignoreAccents
            let options = FullTextIndex.options(ignoreAccents: self.ignoreAccents, locale: self.locale)
            self.impl = CBLIndex.fullTextIndex(with: self.items, options: options)
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
            let options = FullTextIndex.options(ignoreAccents: self.ignoreAccents,
                                           locale: self.locale)
            self.impl = CBLIndex.fullTextIndex(with: self.items, options: options)
        }
        return self
    }
    
    // MARK: Internal
    
    var items: [CBLFullTextIndexItem]
    var ignoreAccents: Bool?
    var locale: String?
    
    init(items: [FullTextIndexItem], ignoreAccents: Bool?, locale: String?) {
        self.items = []
        for item in items {
            self.items.append(item.impl)
        }
        
        self.ignoreAccents = ignoreAccents
        self.locale = locale
        let options = FullTextIndex.options(ignoreAccents: self.ignoreAccents, locale: self.locale)
        super.init(impl: CBLIndex.fullTextIndex(with: self.items, options: options))
    }
    
    class func options(ignoreAccents: Bool?, locale: String?) -> CBLFullTextIndexOptions? {
        let options = CBLFullTextIndexOptions()
        options.ignoreAccents = ignoreAccents ?? false
        options.locale = locale
        return options
    }

}


/// Full-text search index item.
public class FullTextIndexItem {
    
    /// Creates a full-text search index item with the given expression.
    ///
    /// - Parameter expression: The expression to index. Typically a property expression used to
    ///                         perform the match operation against with.
    /// - Returns: The full-text index item.
    public class func property(_ property: String) -> FullTextIndexItem {
        return FullTextIndexItem(impl: CBLFullTextIndexItem.property(property))
    }
    
    // MARK: Internal
    
    let impl: CBLFullTextIndexItem
    
    init(impl: CBLFullTextIndexItem) {
        self.impl = impl
    }
    
}
