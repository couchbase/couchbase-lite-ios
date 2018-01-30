//
//  Index.swift
//  CBL Swift
//
//  Created by Pasin Suriyentrakorn on 8/23/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


public protocol Index { }


/// Index represents an index which could be a value index for regular queries or
/// full-text index for full-text queries (using the match operator).
public class IndexBuilder {
    
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
        return FullTextIndex(items: items)
    }
    
}


// MARK: Value Index


/// A value index for regular queries.
public final class ValueIndex: Index, CBLIndexConvertible {
    
    private let impl: CBLIndex
    
    init(items: [ValueIndexItem]) {
        var cblItems: [CBLValueIndexItem] = []
        for item in items {
            cblItems.append(item.impl)
        }
        impl = CBLIndexBuilder.valueIndex(with: cblItems)
    }
    
    func toImpl() -> CBLIndex {
        return self.impl
    }
    
}


/// Value Index Item.
public final class ValueIndexItem {
    
    public class func property(_ property: String) -> ValueIndexItem {
        return ValueIndexItem(impl: CBLValueIndexItem.property(property))
    }
    
    ///  Creates a value index item with the given expression.
    ///
    /// - Parameter expression: The expression to index. Typically a property expression.
    /// - Returns: The value index item.
    public class func expression(_ expression: ExpressionProtocol) -> ValueIndexItem {
        return ValueIndexItem(impl: CBLValueIndexItem.expression(expression.toImpl()))
    }
    
    // MARK: Internal
    
    let impl: CBLValueIndexItem
    
    init(impl: CBLValueIndexItem) {
        self.impl = impl
    }
    
}


// MARK: FTS Index


/// A full-text search index for full-text search query with the match operator.
public final class FullTextIndex: Index, CBLIndexConvertible {
    
    /// Set to true ignore accents/diacritical marks. The default value is false.
    ///
    /// - Parameter ignoreAccents: The ignore accent value.
    /// - Returns: The FTSIndex instance.
    public func ignoreAccents(_ ignoreAccents: Bool) -> Self {
        self.impl.ignoreAccents = ignoreAccents
        return self
    }
    
    
    /// The language code which is an ISO-639 language code such as "en", "fr", etc.
    /// Setting the language code affects how word breaks and word stems are parsed.
    /// Without setting the language code, the current locale's language will be used.
    /// Setting nil value or "" value to disable the language features.
    ///
    /// - Parameter language: The language code.
    /// - Returns: The FTSIndex instance.
    public func language(_ language: String?) -> Self {
        self.impl.language = language
        return self
    }
    
    // MARK: Internal
    
    private let impl: CBLFullTextIndex
    
    init(items: [FullTextIndexItem]) {
        self.impl = CBLIndexBuilder.fullTextIndex(with: items.map { $0.impl })
    }
    
    func toImpl() -> CBLIndex {
        return self.impl as CBLIndex
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


protocol CBLIndexConvertible {
    func toImpl() -> CBLIndex
}


extension Index {
    func toImpl() -> CBLIndex {
        if let index = self as? CBLIndexConvertible {
            return index.toImpl()
        }
        fatalError("Unsupported index.")
    }
}
