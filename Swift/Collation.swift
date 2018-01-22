//
//  Collation.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 8/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

/// Collation defines how strings are compared and is used when creating a COLLATE expression.
/// The COLLATE expression can be used in the WHERE clause when comparing two strings or in the
/// ORDER BY clause when specifying how the order of the query results.
public protocol CollationProtocol {
    
}

/// Collation factory. CouchbaseLite provides two types of the Collation,
/// ASCII and Unicode. Without specifying the COLLATE expression. Couchbase Lite
/// will use the ASCII with case sensitive collation by default.
public final class Collation {
    
    /// Creates an ASCII collation that will compare two strings by using binary comparison.
    ///
    /// - Returns: The ASCII collation.
    static public func ascii() -> ASCII {
        return ASCII()
    }
    
    /// Creates a Unicode collation that will compare two strings by using Unicode Collation
    /// Algorithm. If the locale is not specified, the collation is Unicode-aware but
    /// not localized; for example, accented Roman letters sort right after the base letter
    /// (This is implemented by using the "en_US" locale.).
    ///
    /// - Returns: The Unicode collation.
    static public func unicode() -> Unicode {
        return Unicode()
    }
    
    /// ASCII collation compares two strings by using binary comparison.
    public final class ASCII: CollationProtocol {
        
        /// Specifies whether the collation is case-sensitive or not. Case-insensitive
        /// collation will treat ASCII uppercase and lowercase letters as equivalent.
        ///
        /// - Parameter ignoreCase: True for case-insenstivie; false for case-senstive.
        /// - Returns: The ASCII Collation object.
        public func ignoreCase(_ ignoreCase: Bool) -> Self {
            self.ignoreCase = ignoreCase
            return self
        }
        
        // MARK: Internal
        

        var ignoreCase = false
        
        
        func toImpl() -> CBLQueryCollation {
            return CBLQueryCollation.ascii(withIgnoreCase: ignoreCase)
        }
    }

    
    /// [Unicode Collation](http://userguide.icu-project.org/collation) that will compare two strings
    /// by using Unicode collation algorithm. If the locale is not specified, the collation is
    /// Unicode-aware but not localized; for example, accented Roman letters sort right after
    /// the base letter (This is implemented by using the "en_US" locale).
    public final class Unicode: CollationProtocol {
        
        
        /// Specifies whether the collation is case-insenstive or not. Case-insensitive
        /// collation will treat ASCII uppercase and lowercase letters as equivalent.
        ///
        /// - Parameter ignoreCase: True for case-insenstivie; false for case-senstive.
        /// - Returns: The Unicode Collation object.
        public func ignoreCase(_ ignoreCase: Bool) -> Self {
            self.ignoreCase = ignoreCase
            return self
        }
        
        
        /// Specifies whether the collation ignore the accents or diacritics when
        /// comparing the strings or not.
        ///
        /// - Parameter ignoreAccents: True for accent-insenstivie; false for accent-senstive.
        /// - Returns: The Unicode Collation object.
        public func ignoreAccents(_ ignoreAccents: Bool) -> Self {
            self.ignoreAccents = ignoreAccents
            return self
        }
        
        
        /// Specifies the locale to allow the collation to compare strings appropriately base on
        /// the locale.
        ///
        /// - Parameter locale: The locale code which is an
        ///                     [ISO-639](https://en.wikipedia.org/wiki/List_of_ISO_639-1_codes)
        ///                     language code plus, optionally, an underscore and an
        ///                     [ISO-3166](https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2)
        ///                     country code: "en", "en_US", "fr_CA", etc.
        ///                     Specifing the locale will allow the collation to compare strings
        ///                     appropriately base on the locale. If not specified, the 'en_US'
        ///                     will be used by default.
        /// - Returns: The Unicode Collation object.
        public func locale(_ locale: String?) -> Self {
            self.locale = locale
            return self
        }
        
        
        // MARK: Internal
        
        
        var ignoreCase = false
        
        var ignoreAccents = false
        
        var locale: String?
        
        func toImpl() -> CBLQueryCollation {
            return CBLQueryCollation.unicode(withLocale: locale,
                                             ignoreCase: ignoreCase,
                                             ignoreAccents: ignoreAccents)
        }
    }
    
}

extension CollationProtocol {
    
    func toImpl() -> CBLQueryCollation {
        if let o = self as? Collation.ASCII {
            return o.toImpl()
        }
        
        if let o = self as? Collation.Unicode {
            return o.toImpl()
        }
        
        fatalError("Unsupported collation.");
    }
    
}
