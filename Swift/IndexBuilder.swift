//
//  IndexBuilder.swift
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

import Foundation

/// Index represents an index which could be a value index for regular queries or
/// full-text index for full-text queries (using the match operator).
public class IndexBuilder {
    
    /// Create a value index with the given index items. The index items are a list of
    /// the properties or expressions to be indexed.
    ///
    /// - Parameter: items The index items.
    /// - Returns: The ValueIndex.
    public static func valueIndex(items: ValueIndexItem...) -> ValueIndex {
        return valueIndex(items: items);
    }
    
    
    /// Create a value index with the given index items. The index items are a list of
    /// the properties or expressions to be indexed.
    ///
    /// - Parameter items: The index items.
    /// - Returns:  The ValueIndex.
    public static func valueIndex(items: [ValueIndexItem]) -> ValueIndex {
        return ValueIndex(items: items)
    }
    
    
    /// Create a full-text index with the given index items. Typically
    /// the index items are the properties that are used to perform the
    /// match operation against with.
    ///
    /// - Parameter: items The index items.
    /// - Returns:  The FullTextIndex.
    public static func fullTextIndex(items: FullTextIndexItem...) -> FullTextIndex {
        return fullTextIndex(items: items)
    }
    
    
    /// Create a full-text index with the given index items. Typically
    /// the index items are the properties that are used to perform the
    /// match operation against with.
    ///
    /// - Parameter: items The index items.
    /// - Returns:  The FullTextIndex.
    public static func fullTextIndex(items: [FullTextIndexItem]) -> FullTextIndex {
        return FullTextIndex(items: items)
    }
    
}
