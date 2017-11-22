//
//  Document.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


/// Couchbase Lite document. The Document is immutable.
public class Document : DictionaryProtocol {
    
    /// The document's ID.
    public var id: String {
        return _impl.id
    }
    
    
    /// Sequence number of the document in the database.
    /// This indicates how recently the document has been changed: every time any document is updated,
    /// the database assigns it the next sequential sequence number. Thus, if a document's `sequence`
    /// property changes that means it's been changed (on-disk); and if one document's `sequence`
    /// is greater than another's, that means it was changed more recently.
    public var sequence: UInt64 {
        return _impl.sequence
    }
    
    
    /// Is the document deleted?
    public var isDeleted: Bool {
        return _impl.isDeleted
    }
    
    
    // TODO: Review the equality behavior of the equal operator.
    /// Equal to operator for comparing two Document object.
    public static func == (doc1: Document, doc: Document) -> Bool {
        return doc._impl === doc._impl
    }
    
    
    // MARK: Edit
    
    
    /// Returns a mutable copy of the document.
    ///
    /// - Returns: The MutableDocument object.
    public func toMutable() -> MutableDocument {
        return MutableDocument(_impl.toMutable())
    }
    

    // MARK: DictionaryProtocol

    
    /// The number of properties in the document.
    public var count: Int {
        return Int(_impl.count)
    }


    /// An array containing all keys, or an empty array if the document has no properties.
    public var keys: Array<String> {
        return _impl.keys
    }
    
    
    /// Gets a property's value. The value types are Blob, ArrayObject,
    /// DictionaryObject, Number, or String based on the underlying data type; or nil
    /// if the value is nil or the property doesn't exist.
    ///
    /// - Parameter key: The key.
    /// - Returns: The value or nil.
    public func value(forKey key: String) -> Any? {
        return DataConverter.convertGETValue(_impl.value(forKey: key))
    }

    
    ///  Gets a property's value as a string.
    ///  Returns nil if the property doesn't exist, or its value is not a string.
    ///
    /// - Parameter key: The key.
    /// - Returns: The String object or nil.
    public func string(forKey key: String) -> String? {
        return _impl.string(forKey: key)
    }
    
    
    /// Get a property's value as an NSNumber object.
    ///
    /// - Parameter key: The key.
    /// - Returns: The NSNumber object.
    public func number(forKey key: String) -> NSNumber? {
        return _impl.number(forKey: key)
    }
    
    
    /// Gets a property's value as an int value.
    /// Floating point values will be rounded. The value `true` is returned as 1, `false` as 0.
    /// Returns 0 if the property doesn't exist or does not have a numeric value.
    ///
    /// - Parameter key: The key.
    /// - Returns: The Int value.
    public func int(forKey key: String) -> Int {
        return _impl.integer(forKey: key)
    }
    
    
    /// Gets a property's value as an int64 value.
    /// Floating point values will be rounded. The value `true` is returned as 1, `false` as 0.
    /// Returns 0 if the property doesn't exist or does not have a numeric value.
    ///
    /// - Parameter key: The key.
    /// - Returns: The Int64 value.
    public func int64(forKey key: String) -> Int64 {
        return _impl.longLong(forKey: key)
    }
    
    
    /// Gets a property's value as a float value.
    /// Integers will be converted to float. The value `true` is returned as 1.0, `false` as 0.0.
    /// Returns 0.0 if the property doesn't exist or does not have a numeric value.
    ///
    /// - Parameter key: The key.
    /// - Returns: The Float value.
    public func float(forKey key: String) -> Float {
        return _impl.float(forKey: key)
    }
    
    
    /// Gets a property's value as a double value.
    /// Integers will be converted to double. The value `true` is returned as 1.0, `false` as 0.0.
    /// Returns 0.0 if the property doesn't exist or does not have a numeric value.
    ///
    /// - Parameter key: The key.
    /// - Returns: The Double value.
    public func double(forKey key: String) -> Double {
        return _impl.double(forKey: key)
    }
    
    
    // TODO: Review the behavior of getting boolean value
    /// Gets a property's value as a boolean value.
    /// Returns true if the value exists, and is either `true` or a nonzero number.
    ///
    /// - Parameter key: The key.
    /// - Returns: The Bool value.
    public func boolean(forKey key: String) -> Bool {
        return _impl.boolean(forKey: key)
    }
    
    
    /// Get a property's value as a Blob object.
    /// Returns nil if the property doesn't exist, or its value is not a blob.
    ///
    /// - Parameter key: The key.
    /// - Returns: The Blob object or nil.
    public func blob(forKey key: String) -> Blob? {
        return _impl.blob(forKey: key)
    }
    
    
    /// Gets a property's value as a Date value.
    /// JSON does not directly support dates, so the actual property value must be a string, which is
    /// then parsed according to the ISO-8601 date format (the default used in JSON.)
    /// Returns nil if the value doesn't exist, is not a string, or is not parseable as a date.
    /// NOTE: This is not a generic date parser! It only recognizes the ISO-8601 format, with or
    /// without milliseconds.
    ///
    /// - Parameter key: The key.
    /// - Returns: The Date value or nil
    public func date(forKey key: String) -> Date? {
        return _impl.date(forKey: key)
    }
    

    /// Get a property's value as a ArrayObject, which is a mapping object of an array value.
    /// Returns nil if the property doesn't exists, or its value is not an array.
    ///
    /// - Parameter key: The key.
    /// - Returns: The ArrayObject object or nil.
    public func array(forKey key: String) -> ArrayObject? {
        return value(forKey: key) as? ArrayObject
    }


    /// Get a property's value as a DictionaryObject, which is a mapping object of
    /// a dictionary value.
    /// Returns nil if the property doesn't exists, or its value is not a dictionary.
    ///
    /// - Parameter key: The key.
    /// - Returns: THe DictionaryObject object or nil.
    public func dictionary(forKey key: String) -> DictionaryObject? {
        return value(forKey: key) as? DictionaryObject
    }


    /// Tests whether a property exists or not.
    /// This can be less expensive than value(forKey:), because it does not have to allocate an
    /// object for the property value.
    ///
    /// - Parameter key: The key.
    /// - Returns: True of the property exists, otherwise false.
    public func contains(key: String) -> Bool {
        return _impl.containsValue(forKey: key)
    }

    
    // MARK: Data
    

    /// Gets content of the document as a Dictionary. The values contained in the
    /// returned Dictionary object are all JSON based values.
    ///
    /// - Returns: The Dictionary object representing the content of the current object in the
    ///            JSON format.
    public func toDictionary() -> Dictionary<String, Any> {
        return _impl.toDictionary()
    }


    // MARK: Sequence


    /// Gets  an iterator over the keys of the document's properties
    ///
    /// - Returns: The key iterator.
    public func makeIterator() -> IndexingIterator<[String]> {
        return _impl.keys.makeIterator();
    }


    // MARK: Subscript


    /// Subscript access to a Fragment object by key.
    ///
    /// - Parameter key: The key.
    public subscript(key: String) -> Fragment {
        return Fragment(_impl[key])
    }


    // MARK: Internal
    
    
    init(_ impl: CBLDocument) {
        _impl = impl
    }
    
    
    // MARK: Private
    
    
    let _impl: CBLDocument
    
}
