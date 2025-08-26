//
//  VectorSearchTest+Lazy.swift
//  CouchbaseLite
//
//  Copyright (c) 2024 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Couchbase License Agreement (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//  https://info.couchbase.com/rs/302-GJY-034/images/2017-10-30_License_Agreement.pdf
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#if COUCHBASE_ENTERPRISE

import XCTest
@testable import CouchbaseLiteSwift

///
/// Test Spec :
/// https://github.com/couchbaselabs/couchbase-lite-api/blob/master/spec/tests/T0002-Lazy-Vector-Index.md
///
/// Vesion: 2.0.1
///
/// Note:
/// - Tested in Objective-C
///      - Test 4 TestGetExistingNonVectorIndex
///      - Test 8 TestLazyVectorIndexNotAutoUpdatedChangedDocs
///      - Test 9 TestLazyVectorIndexAutoUpdateDeletedDocs
///      - Test 10 TestLazyVectorIndexAutoUpdatePurgedDocs
///      - Test 11 TestIndexUpdaterBeginUpdateOnNonVectorIndex
///      - Test 20 TestIndexUpdaterSetInvalidVectorDimensions
///      - Test 22 TestIndexUpdaterFinishWithIncompletedUpdate
///      - Test 23 TestIndexUpdaterCaughtUp
///      - Test 24 TestNonFinishedIndexUpdaterNotUpdateIndex
///      - Test 26 TestIndexUpdaterCallFinishTwice
///      - Test 27 TestIndexUpdaterUseAfterFinished
/// - Test 6 TestGetIndexOnClosedDatabase is done in CollectionTest.testUseCollectionAPIWhenDatabaseIsClosed()
/// - Test 7 testInvalidCollection) is done in CollectionTest.testUseCollectionAPIOnDeletedCollection()
///
class VectorSearchTest_Lazy : VectorSearchTest {
    /// Override the default VectorSearch Expression
    override func wordsQueryDefaultExpression() -> String{
        return "word"
    }
    
    func wordsIndex() throws -> QueryIndex {
        let index = try wordsCollection.index(withName: wordsIndexName)
        XCTAssertNotNil(index)
        return index!
    }
    
    func lazyConfig(_ config: VectorIndexConfiguration) -> VectorIndexConfiguration {
        var nuConfig = config
        nuConfig.isLazy = true
        return nuConfig
    }
    
    func vector(forWord word: String) -> [Float]? {
        let model = WordEmbeddingModel(db: wordDB)
        if let vector = model.getWordVector(word: word, collection: wordsCollectionName) {
            return vector.toArray() as? [Float]
        }
        if let vector = model.getWordVector(word: word, collection: extWordsCollectionName) {
            return vector.toArray() as? [Float]
        }
        return nil
    }
    
    /// 1. TestIsLazyDefaultValue
    ///
    /// Description
    /// Test that isLazy property is false by default.
    ///
    /// Steps
    /// 1. Create a VectorIndexConfiguration object.
    ///     - expression: “vector”
    ///     - dimensions: 300
    ///     - centroids : 20
    /// 2. Check that isLazy returns false.
    func testIsLazyDefaultValue() throws {
        let config = VectorIndexConfiguration(expression: "vector", dimensions: 300, centroids: 20)
        XCTAssertFalse(config.isLazy)
    }
    
    /// 2. TestIsLazyAccessor
    ///
    /// Description
    /// Test that isLazy getter/setter of the VectorIndexConfiguration work as expected.
    ///
    /// Steps
    /// 1. Create a VectorIndexConfiguration object.
    ///    - expression: word
    ///    - dimensions: 300
    ///    - centroids : 20
    /// 2. Set isLazy to true
    /// 3. Check that isLazy returns true.
    func testIsLazyAccessor() throws {
        var config = VectorIndexConfiguration(expression: "vector", dimensions: 300, centroids: 20)
        config.isLazy = true
        XCTAssertTrue(config.isLazy)
    }
    
    /// 3. TestGetNonExistingIndex
    ///
    /// Description
    /// Test that getting non-existing index object by name returning null.
    ///
    /// Steps
    /// 1. Get the default collection from a test database.
    /// 2. Get a QueryIndex object from the default collection with the name as
    ///    "nonexistingindex".
    /// 3. Check that the result is null.
    func testGetNonExistingIndex() throws {
        let collection = try db.defaultCollection()
        let index = try collection.index(withName: "nonexistingindex")
        XCTAssertNil(index)
    }
    
    /// 5. TestGetExistingVectorIndex
    ///
    /// Description
    /// Test that getting an existing index object by name returning an index object correctly.
    ///
    /// Steps
    /// 1. Copy database words_db.
    /// 2. Create a vector index named "words_index" in the _default.words collection.
    ///     - expression: "word"
    ///     - dimensions: 300
    ///     - centroids : 8
    /// 3. Get a QueryIndex object from the words collection with the name as
    ///    "words_index".
    /// 4. Check that the result is not null.
    /// 5. Check that the QueryIndex's name is "words_index".
    /// 6. Check that the QueryIndex's collection is the same instance that is used for
    ///   getting the index.
    func testGetExistingVectorIndex() throws {
        let config = VectorIndexConfiguration(expression: "vector", dimensions: 300, centroids: 8)
        try createWordsIndex(config: config)
        let index = try wordsIndex()
        XCTAssertEqual(index.name, wordsIndexName)
        XCTAssert(index.collection === wordsCollection)
    }
    
    /// 12. TestIndexUpdaterBeginUpdateOnNonLazyVectorIndex
    ///
    /// Description
    /// Test that a CouchbaseLiteException is thrown when calling beginUpdate
    /// on a non lazy vector index.
    ///
    /// Steps
    /// 1. Copy database words_db.
    /// 2. Create a vector index named "words_index" in the _default.words collecti
    ///     - expression: "word"
    ///     - dimensions: 300
    ///     - centroids : 8
    /// 3. Get a QueryIndex object from the words collection with the name as
    ///    "words_index".
    /// 4. Call beginUpdate() with limit 10 on the QueryIndex object.
    /// 5. Check that a CouchbaseLiteException with the code Unsupported is thrown.
    func testIndexUpdaterBeginUpdateOnNonLazyVectorIndex() throws {
        let config = VectorIndexConfiguration(expression: "vector", dimensions: 300, centroids: 8)
        try createWordsIndex(config: config)
        
        let index = try wordsIndex()
        
        expectError(domain: CBLError.domain, code: CBLError.unsupported) {
            _ = try index.beginUpdate(limit: 10)
        }
    }
    
    /// 13. TestIndexUpdaterBeginUpdateWithZeroLimit
    ///
    /// Description
    /// Test that an InvalidArgument exception is returned when calling beginUpdate
    /// with zero limit.
    ///
    /// Steps
    /// 1. Copy database words_db.
    /// 2. Create a vector index named "words_index" in the _default.words collection.
    ///     - expression: "word"
    ///     - dimensions: 300
    ///     - centroids : 8
    ///     - isLazy : true
    /// 3. Get a QueryIndex object from the words collection with the name as
    ///    "words_index".
    /// 4. Call beginUpdate() with limit 0 on the QueryIndex object.
    /// 5. Check that an InvalidArgumentException is thrown.
    func testIndexUpdaterBeginUpdateWithZeroLimit() throws {
        let config = VectorIndexConfiguration(expression: "vector", dimensions: 300, centroids: 8)
        try createWordsIndex(config: config)
        
        let index = try wordsIndex()
        
        expectException(exception: .invalidArgumentException) {
            _ = try? index.beginUpdate(limit: 0)
        }
    }
    
    /// 14. TestIndexUpdaterBeginUpdateOnLazyVectorIndex
    ///
    /// Description
    /// Test that calling beginUpdate on a lazy vector index returns an IndexUpdater.
    ///
    /// Steps
    /// 1. Copy database words_db.
    /// 2. Create a vector index named "words_index" in the _default.words collection.
    ///     - expression: "word"
    ///     - dimensions: 300
    ///     - centroids : 8
    ///     - isLazy : true
    /// 3. Get a QueryIndex object from the words with the name as "words_index".
    /// 4. Call beginUpdate() with limit 10 on the QueryIndex object.
    /// 5. Check that the returned IndexUpdater is not null.
    /// 6. Check that the IndexUpdater.count is 10.
    func testIndexUpdaterBeginUpdateOnLazyVectorIndex() throws {
        let config = VectorIndexConfiguration(expression: "vector", dimensions: 300, centroids: 8)
        try createWordsIndex(config: lazyConfig(config))
        
        let index = try wordsIndex()
        let updater = try index.beginUpdate(limit: 10)
        XCTAssertNotNil(updater)
        XCTAssertEqual(updater?.count, 10)
    }
    
    /// 15. TestIndexUpdaterGettingValues
    ///
    /// Description
    /// Test all type getters and toArary() from the Array interface. The test
    /// may be divided this test into multiple tests per type getter as appropriate.
    ///
    /// Steps
    /// 1. Get the default collection from a test database.
    /// 2. Create the followings documents:
    ///     - doc-0 : { "value": "a string" }
    ///     - doc-1 : { "value": 100 }
    ///     - doc-2 : { "value": 20.8 }
    ///     - doc-3 : { "value": true }
    ///     - doc-4 : { "value": false }
    ///     - doc-5 : { "value": Date("2024-05-10T00:00:00.000Z") }
    ///     - doc-6 : { "value": Blob(Data("I'm Bob")) }
    ///     - doc-7 : { "value": {"name": "Bob"} }
    ///     - doc-8 : { "value": ["one", "two", "three"] }
    ///     - doc-9 : { "value": null }
    /// 3. Create a vector index named "vector_index" in the default collection.
    ///     - expression: "value"
    ///     - dimensions: 300
    ///     - centroids : 8
    ///     - isLazy : true
    /// 4. Get a QueryIndex object from the default collection with the name as
    ///    "vector_index".
    /// 5. Call beginUpdate() with limit 10 to get an IndexUpdater object.
    /// 6. Check that the IndexUpdater.count is 10.
    /// 7. Get string value from each index and check the followings:
    ///     - getString(0) : value == "a string"
    ///     - getString(1) : value == null
    ///     - getString(2) : value == null
    ///     - getString(3) : value == null
    ///     - getString(4) : value == null
    ///     - getString(5) : value == "2024-05-10T00:00:00.000Z"
    ///     - getString(6) : value == null
    ///     - getString(7) : value == null
    ///     - getString(8) : value == null
    ///     - getString(9) : value == null
    /// 8. Get integer value from each index and check the followings:
    ///     - getInt(0) : value == 0
    ///     - getInt(1) : value == 100
    ///     - getInt(2) : value == 20
    ///     - getInt(3) : value == 1
    ///     - getInt(4) : value == 0
    ///     - getInt(5) : value == 0
    ///     - getInt(6) : value == 0
    ///     - getInt(7) : value == 0
    ///     - getInt(8) : value == 0
    ///     - getInt(9) : value == 0
    /// 9. Get float value from each index and check the followings:
    ///     - getFloat(0) : value == 0.0
    ///     - getFloat(1) : value == 100.0
    ///     - getFloat(2) : value == 20.8
    ///     - getFloat(3) : value == 1.0
    ///     - getFloat(4) : value == 0.0
    ///     - getFloat(5) : value == 0.0
    ///     - getFloat(6) : value == 0.0
    ///     - getFloat(7) : value == 0.0
    ///     - getFloat(8) : value == 0.0
    ///     - getFloat(9) : value == 0.0
    /// 10. Get double value from each index and check the followings:
    ///     - getDouble(0) : value == 0.0
    ///     - getDouble(1) : value == 100.0
    ///     - getDouble(2) : value == 20.8
    ///     - getDouble(3) : value == 1.0
    ///     - getDouble(4) : value == 0.0
    ///     - getDouble(5) : value == 0.0
    ///     - getDouble(6) : value == 0.0
    ///     - getDouble(7) : value == 0.0
    ///     - getDouble(8) : value == 0.0
    ///     - getDouble(9) : value == 0.0
    /// 11. Get boolean value from each index and check the followings:
    ///     - getBoolean(0) : value == true
    ///     - getBoolean(1) : value == true
    ///     - getBoolean(2) : value == true
    ///     - getBoolean(3) : value == true
    ///     - getBoolean(4) : value == false
    ///     - getBoolean(5) : value == true
    ///     - getBoolean(6) : value == true
    ///     - getBoolean(7) : value == true
    ///     - getBoolean(8) : value == true
    ///     - getBoolean(9) : value == false
    /// 12. Get date value from each index and check the followings:
    ///     - getDate(0) : value == null
    ///     - getDate(1) : value == null
    ///     - getDate(2) : value == null
    ///     - getDate(3) : value == null
    ///     - getDate(4) : value == null
    ///     - getDate(5) : value == Date("2024-05-10T00:00:00.000Z")
    ///     - getDate(6) : value == null
    ///     - getDate(7) : value == null
    ///     - getDate(8) : value == null
    ///     - getDate(9) : value == null
    /// 13. Get blob value from each index and check the followings:
    ///     - getBlob(0) : value == null
    ///     - getBlob(1) : value == null
    ///     - getBlob(2) : value == null
    ///     - getBlob(3) : value == null
    ///     - getBlob(4) : value == null
    ///     - getBlob(5) : value == null
    ///     - getBlob(6) : value == Blob(Data("I'm Bob"))
    ///     - getBlob(7) : value == null
    ///     - getBlob(8) : value == null
    ///     - getBlob(9) : value == null
    /// 14. Get dictionary object from each index and check the followings:
    ///     - getDictionary(0) : value == null
    ///     - getDictionary(1) : value == null
    ///     - getDictionary(2) : value == null
    ///     - getDictionary(3) : value == null
    ///     - getDictionary(4) : value == null
    ///     - getDictionary(5) : value == null
    ///     - getDictionary(6) : value == null
    ///     - getDictionary(7) : value == Dictionary({"name": "Bob"})
    ///     - getDictionary(8) : value == null
    ///     - getDictionary(9) : value == null
    /// 15. Get array object from each index and check the followings:
    ///     - getArray(0) : value == null
    ///     - getArray(1) : value == null
    ///     - getArray(2) : value == null
    ///     - getArray(3) : value == null
    ///     - getArray(4) : value == null
    ///     - getArray(5) : value == null
    ///     - getArray(6) : value == null
    ///     - getArray(7) : value == null
    ///     - getArray(8) : value == Array(["one", "two", "three"])
    ///     - getArray(9) : value == null
    /// 16. Get value from each index and check the followings:
    ///     - getValue(0) : value == "a string"
    ///     - getValue(1) : value == PlatformNumber(100)
    ///     - getValue(2) : value == PlatformNumber(20.8)
    ///     - getValue(3) : value == PlatformBoolean(true)
    ///     - getValue(4) : value == PlatformBoolean(false)
    ///     - getValue(5) : value == "2024-05-10T00:00:00.000Z"
    ///     - getValue(6) : value == Blob(Data("I'm Bob"))
    ///     - getValue(7) : value == PlatformDict({"name": "Bob"})
    ///     - getValue(8) : value == PlatformArray(["one", "two", "three"])
    ///     - getValue(9) : value == null
    /// 17. Get IndexUodater values as a platform array by calling toArray() and check
    ///     that the array contains all values as expected.
    func testIndexUpdaterGettingValues() throws {
        let collection = try db.defaultCollection()
        
        let doc0 = createDocument(data: ["value": "a string"])
        try collection.save(document: doc0)
        
        let doc1 = createDocument(data: ["value": 100])
        try collection.save(document: doc1)
        
        let doc2 = createDocument(data: ["value": 20.8])
        try collection.save(document: doc2)
        
        let doc3 = createDocument(data: ["value": true])
        try collection.save(document: doc3)
        
        let doc4 = createDocument(data: ["value": false])
        try collection.save(document: doc4)
        
        let date = dateFromJson("2024-05-10T00:00:00.000Z")
        let doc5 = createDocument(data: ["value": date])
        try collection.save(document: doc5)
        
        let content = "I'm Bob".data(using: .utf8)!
        let blob = Blob(contentType: "text/plain", data: content)
        let doc6 = createDocument(data: ["value": blob])
        try collection.save(document: doc6)
        
        let doc7 = createDocument(data: ["value": ["name": "Bob"]])
        try collection.save(document: doc7)
        
        let doc8 = createDocument(data: ["value": ["one", "two", "three"]])
        try collection.save(document: doc8)
        
        let doc9 = createDocument(data: ["value": NSNull()])
        try collection.save(document: doc9)
        
        let config = VectorIndexConfiguration(expression: "value", dimensions: 300, centroids: 8)
        try createVectorIndex(collection: collection, name: "vector_index", config: lazyConfig(config))
        
        let index = try collection.index(withName: "vector_index")
        XCTAssertNotNil(index)
        
        let indexUpdater = try index!.beginUpdate(limit: 10)
        XCTAssertNotNil(indexUpdater)
        XCTAssertEqual(indexUpdater!.count, 10)
        
        let updater = indexUpdater!
        
        // String:
        XCTAssertEqual(updater.string(at: 0), "a string")
        XCTAssertNil(updater.string(at: 1))
        XCTAssertNil(updater.string(at: 2))
        XCTAssertNil(updater.string(at: 3))
        XCTAssertNil(updater.string(at: 4))
        XCTAssertEqual(updater.string(at: 5), "2024-05-10T00:00:00.000Z")
        XCTAssertNil(updater.string(at: 6))
        XCTAssertNil(updater.string(at: 7))
        XCTAssertNil(updater.string(at: 8))
        XCTAssertNil(updater.string(at: 9))
        
        // Int:
        XCTAssertEqual(updater.int(at: 0), 0)
        XCTAssertEqual(updater.int(at: 1), 100)
        XCTAssertEqual(updater.int(at: 2), 20)
        XCTAssertEqual(updater.int(at: 3), 1)
        XCTAssertEqual(updater.int(at: 4), 0)
        XCTAssertEqual(updater.int(at: 5), 0)
        XCTAssertEqual(updater.int(at: 6), 0)
        XCTAssertEqual(updater.int(at: 7), 0)
        XCTAssertEqual(updater.int(at: 8), 0)
        XCTAssertEqual(updater.int(at: 9), 0)
        
        // Int64:
        XCTAssertEqual(updater.int64(at: 0), 0)
        XCTAssertEqual(updater.int64(at: 1), 100)
        XCTAssertEqual(updater.int64(at: 2), 20)
        XCTAssertEqual(updater.int64(at: 3), 1)
        XCTAssertEqual(updater.int64(at: 4), 0)
        XCTAssertEqual(updater.int64(at: 5), 0)
        XCTAssertEqual(updater.int64(at: 6), 0)
        XCTAssertEqual(updater.int64(at: 7), 0)
        XCTAssertEqual(updater.int64(at: 8), 0)
        XCTAssertEqual(updater.int64(at: 9), 0)
        
        // Float:
        XCTAssertEqual(updater.float(at: 0), 0.0)
        XCTAssertEqual(updater.float(at: 1), 100.0)
        XCTAssertEqual(updater.float(at: 2), 20.8)
        XCTAssertEqual(updater.float(at: 3), 1.0)
        XCTAssertEqual(updater.float(at: 4), 0)
        XCTAssertEqual(updater.float(at: 5), 0)
        XCTAssertEqual(updater.float(at: 6), 0)
        XCTAssertEqual(updater.float(at: 7), 0)
        XCTAssertEqual(updater.float(at: 8), 0)
        XCTAssertEqual(updater.float(at: 9), 0)
        
        // Double:
        XCTAssertEqual(updater.double(at: 0), 0.0)
        XCTAssertEqual(updater.double(at: 1), 100.0)
        XCTAssertEqual(updater.double(at: 2), 20.8)
        XCTAssertEqual(updater.double(at: 3), 1.0)
        XCTAssertEqual(updater.double(at: 4), 0)
        XCTAssertEqual(updater.double(at: 5), 0)
        XCTAssertEqual(updater.double(at: 6), 0)
        XCTAssertEqual(updater.double(at: 7), 0)
        XCTAssertEqual(updater.double(at: 8), 0)
        XCTAssertEqual(updater.double(at: 9), 0)
        
        // Boolean:
        XCTAssertEqual(updater.boolean(at: 0), true)
        XCTAssertEqual(updater.boolean(at: 1), true)
        XCTAssertEqual(updater.boolean(at: 2), true)
        XCTAssertEqual(updater.boolean(at: 3), true)
        XCTAssertEqual(updater.boolean(at: 4), false)
        XCTAssertEqual(updater.boolean(at: 5), true)
        XCTAssertEqual(updater.boolean(at: 6), true)
        XCTAssertEqual(updater.boolean(at: 7), true)
        XCTAssertEqual(updater.boolean(at: 8), true)
        XCTAssertEqual(updater.boolean(at: 9), false)
        
        // Date:
        XCTAssertNil(updater.date(at: 0))
        XCTAssertNil(updater.date(at: 1))
        XCTAssertNil(updater.date(at: 2))
        XCTAssertNil(updater.date(at: 3))
        XCTAssertNil(updater.date(at: 4))
        let getDate = updater.date(at: 5)
        XCTAssertNotNil(getDate)
        XCTAssertEqual(jsonFromDate(getDate!), "2024-05-10T00:00:00.000Z")
        XCTAssertNil(updater.date(at: 6))
        XCTAssertNil(updater.date(at: 7))
        XCTAssertNil(updater.date(at: 8))
        XCTAssertNil(updater.date(at: 9))
        
        // Blob:
        XCTAssertNil(updater.blob(at: 0))
        XCTAssertNil(updater.blob(at: 1))
        XCTAssertNil(updater.blob(at: 2))
        XCTAssertNil(updater.blob(at: 3))
        XCTAssertNil(updater.blob(at: 4))
        XCTAssertNil(updater.blob(at: 5))
        let getBlob = updater.blob(at: 6)
        XCTAssertNotNil(getBlob)
        XCTAssertEqual(getBlob!.content, content)
        XCTAssertNil(updater.blob(at: 7))
        XCTAssertNil(updater.blob(at: 8))
        XCTAssertNil(updater.blob(at: 9))
        
        // Dict:
        XCTAssertNil(updater.dictionary(at: 0))
        XCTAssertNil(updater.dictionary(at: 1))
        XCTAssertNil(updater.dictionary(at: 2))
        XCTAssertNil(updater.dictionary(at: 3))
        XCTAssertNil(updater.dictionary(at: 4))
        XCTAssertNil(updater.dictionary(at: 5))
        XCTAssertNil(updater.dictionary(at: 6))
        let dict = updater.dictionary(at: 7)
        XCTAssertNotNil(dict)
        XCTAssertTrue(dict! == doc7.dictionary(forKey: "value"))
        XCTAssertNil(updater.dictionary(at: 8))
        XCTAssertNil(updater.dictionary(at: 9))
        
        // Array:
        XCTAssertNil(updater.array(at: 0))
        XCTAssertNil(updater.array(at: 1))
        XCTAssertNil(updater.array(at: 2))
        XCTAssertNil(updater.array(at: 3))
        XCTAssertNil(updater.array(at: 4))
        XCTAssertNil(updater.array(at: 5))
        XCTAssertNil(updater.array(at: 6))
        XCTAssertNil(updater.array(at: 7))
        let array = updater.array(at: 8)
        XCTAssertNotNil(array)
        XCTAssertTrue(array! == doc8.array(forKey: "value"))
        XCTAssertNil(updater.array(at: 9))
        
        // value:
        XCTAssertTrue(updater.value(at: 0) as? String == "a string")
        XCTAssertTrue(updater.value(at: 1) as? Int == 100)
        XCTAssertTrue(updater.value(at: 2) as? Double == 20.8)
        XCTAssertTrue(updater.value(at: 3) as? Bool == true)
        XCTAssertTrue(updater.value(at: 4) as? Bool == false)
        XCTAssertTrue(updater.value(at: 5) as? String == "2024-05-10T00:00:00.000Z")
        XCTAssertTrue(updater.value(at: 6) as? Blob == blob)
        XCTAssertTrue(updater.value(at: 7) as? DictionaryObject == doc7.dictionary(forKey: "value"))
        XCTAssertTrue(updater.value(at: 8) as? ArrayObject == doc8.array(forKey: "value"))
        XCTAssertTrue(updater.value(at: 9) as? NSNull == NSNull())
        
        // toArray
        let values = updater.toArray()
        XCTAssertTrue(values[0] as? String == "a string")
        XCTAssertTrue(values[1] as? Int == 100)
        XCTAssertTrue(values[2] as? Double == 20.8)
        XCTAssertTrue(values[3] as? Bool == true)
        XCTAssertTrue(values[4] as? Bool == false)
        XCTAssertTrue(values[5] as? String == "2024-05-10T00:00:00.000Z")
        XCTAssertTrue(values[6] as? Blob == blob)
        XCTAssertTrue(values[7] as! Dictionary == doc7.dictionary(forKey: "value")!.toDictionary())
        XCTAssertTrue(values[8] as! Array == doc8.array(forKey: "value")!.toArray())
        XCTAssertTrue(values[9] as? NSNull == NSNull())
        
        // toJSON
        XCTAssertTrue(updater.toJSON().count > 0)
    }
    
    /// 16. TestIndexUpdaterArrayIterator
    ///
    /// Description
    /// Test that iterating the index updater using the platform array iterator
    /// interface works as expected.
    ///
    /// Steps
    /// 1. Copy database words_db.
    /// 2. Create a vector index named "words_index" in the _default.words collection.
    ///     - expression: "word"
    ///     - dimensions: 300
    ///     - centroids : 8
    ///     - isLazy : true
    /// 3. Get a QueryIndex object from the words with the name as "words_index".
    /// 4. Call beginUpdate() with limit 10 to get an IndexUpdater object.
    /// 5. Check that the IndexUpdater.count is 10.
    /// 6. Iterate using the platfrom array iterator.
    /// 7. For each iteration, check that the value is the same as the value getting
    ///    from getValue(index).
    /// 8. Check that there were 10 iteration calls.
    func testIndexUpdaterArrayIterator() throws {
        let config = VectorIndexConfiguration(expression: "vector", dimensions: 300, centroids: 8)
        try createWordsIndex(config: lazyConfig(config))
        
        let index = try wordsIndex()
        let updater = try index.beginUpdate(limit: 10)!
        var i = 0
        for value in updater {
            XCTAssertEqual(value as? String, updater[i].string)
            i = i+1
        }
        XCTAssertEqual(i, 10)
    }
    
    /// 17. TestIndexUpdaterSetFloatArrayVectors
    ///
    /// Description
    /// Test that setting float array vectors works as expected.
    ///
    /// Steps
    /// 1. Copy database words_db.
    /// 2. Create a vector index named "words_index" in the _default.words collection.
    ///     - expression: "word"
    ///     - dimensions: 300
    ///     - centroids : 8
    ///     - isLazy : true
    /// 3. Get a QueryIndex object from the words with the name as "words_index".
    /// 4. Call beginUpdate() with limit 10 to get an IndexUpdater object.
    /// 5. With the IndexUpdater object, for each index from 0 to 9.
    ///     - Get the word string from the IndexUpdater and store the word string in a set for verifying
    ///        the vector search result.
    ///     - Query the vector by word from the _default.words collection.
    ///     - Convert the vector result which is an array object to a platform's float array.
    ///     - Call setVector() with the platform's float array at the index.
    /// 6. With the IndexUpdater object, call finish()
    /// 7. Execute a vector search query.
    ///     - SELECT word
    ///       FROM _default.words
    ///       ORDER BY APPROX_VECTOR_DISTANCE(word, $dinnerVector)
    ///       LIMIT 300
    /// 8. Check that there are 10 words returned.
    /// 9. Check that the word is in the word set from the step 5.
    func testIndexUpdaterSetFloatArrayVectors() throws {
        let config = VectorIndexConfiguration(expression: "word", dimensions: 300, centroids: 8)
        try createWordsIndex(config: lazyConfig(config))
        
        let index = try wordsIndex()
        let updater = try index.beginUpdate(limit: 10)!
        XCTAssertEqual(updater.count, 10)
        
        var words: [String] = [];
        for i in 0..<updater.count {
            let word = updater.string(at: i)!
            let vector = vector(forWord: word)!
            try updater.setVector(vector, at: i)
            words.append(word)
        }
        try updater.finish()
        
        let rs = try executeWordsQuery(limit: 300, checkTraining: false)
        let resultWords = toDocIDWordMap(rs: rs).values
        XCTAssertEqual(resultWords.count, 10)
        for word in resultWords {
            XCTAssertTrue(words.contains(word))
        }
    }
    
    /// 21. TestIndexUpdaterSkipVectors
    ///
    /// Description
    /// Test that skipping vectors works as expected.
    ///
    /// Steps
    /// 1. Copy database words_db.
    /// 2. Create a vector index named "words_index" in the _default.words collection.
    ///     - expression: "word"
    ///     - dimensions: 300
    ///     - centroids : 8
    ///     - isLazy : true
    /// 3. Get a QueryIndex object from the words with the name as "words_index".
    /// 4. Call beginUpdate() with limit 10 to get an IndexUpdater object.
    /// 5. With the IndexUpdater object, for each index from 0 - 9.
    ///     - Get the word string from the IndexUpdater.
    ///     - If index % 2 == 0,
    ///         - Store the word string in a skipped word set for verifying the skipped words later.
    ///         - Call skipVector at the index.
    ///     - If index % 2 != 0,
    ///         - Query the vector by word from the _default.words collection.
    ///         - Convert the vector result which is an array object to a platform's float array.
    ///         - Call setVector() with the platform's float array at the index.
    /// 6. With the IndexUpdater object, call finish()
    /// 7. Call beginUpdate with limit 10 to get an IndexUpdater object.
    /// 8. With the IndexUpdater object, for each index
    ///     - Get the word string from the dictionary for the key named "word".
    ///     - Check if the word is in the skipped word set from the Step 5. If the word
    ///        is in the skipped word set, remove the word from the skipped word set.
    ///     - Query the vector by word from the _default.words collection.
    ///         - Convert the vector result which is an array object to a platform's float array.
    ///         - Call setVector() with the platform's float array at the index
    /// 9. With the IndexUpdater object, call finish()
    /// 10. Repeat Step 7, until the returned IndexUpdater is null or the skipped word set
    ///      has zero words in it.
    /// 11. Verify that the skipped word set has zero words in it.
    func testIndexUpdaterSkipVectors() throws {
        let config = VectorIndexConfiguration(expression: "word", dimensions: 300, centroids: 8)
        try createWordsIndex(config: lazyConfig(config))
        
        let index = try wordsIndex()
        var updater = try index.beginUpdate(limit: 10)!
        XCTAssertEqual(updater.count, 10)
        
        var skipWords: [String] = [];
        for i in 0..<updater.count {
            let word = updater.string(at: i)!
            if i % 2 == 0 {
                updater.skipVector(at: i)
                skipWords.append(word)
            } else {
                let vector = vector(forWord: word)!
                try updater.setVector(vector, at: i)
            }
        }
        try updater.finish()
        
        updater = try index.beginUpdate(limit: 10)!
        for i in 0..<updater.count {
            let word = updater.string(at: i)!
            let vector = vector(forWord: word)!
            try updater.setVector(vector, at: i)
            
            if let index = skipWords.firstIndex(of: word) {
                skipWords.remove(at: index)
            }
        }
        try updater.finish()
        XCTAssertEqual(skipWords.count, 0)
    }
    
    /// 25. TestIndexUpdaterIndexOutOfBounds
    ///
    /// Description
    /// Test that when using getter, setter, and skip function with the index that
    /// is out of bounds, an IndexOutOfBounds or InvalidArgument exception
    /// is throws.
    ///
    /// Steps
    /// 1. Get the default collection from a test database.
    /// 2. Create the followings documents:
    ///     - doc-0 : { "value": "a string" }
    /// 3. Create a vector index named "vector_index" in the default collection.
    ///     - expression: "value"
    ///     - dimensions: 3
    ///     - centroids : 8
    ///     - isLazy : true
    /// 4. Get a QueryIndex object from the default collection with the name as
    ///    "vector_index".
    /// 5. Call beginUpdate() with limit 10 to get an IndexUpdater object.
    /// 6. Check that the IndexUpdater.count is 1.
    /// 7. Call each getter function with index = -1 and check that
    ///    an IndexOutOfBounds or InvalidArgument exception is thrown.
    /// 8. Call each getter function with index = 1 and check that
    ///    an IndexOutOfBounds or InvalidArgument exception is thrown.
    /// 9. Call setVector() function with a vector = [1.0, 2.0, 3.0] and index = -1 and check that
    ///    an IndexOutOfBounds or InvalidArgument exception is thrown.
    /// 10. Call setVector() function with a vector = [1.0, 2.0, 3.0] and index = 1 and check that
    ///    an IndexOutOfBounds or InvalidArgument exception is thrown.
    /// 9. Call skipVector() function with index = -1 and check that
    ///    an IndexOutOfBounds or InvalidArgument exception is thrown.
    /// 10. Call skipVector() function with index = 1 and check that
    ///    an IndexOutOfBounds or InvalidArgument exception is thrown.
    func testIndexUpdaterIndexOutOfBounds() throws {
        let collection = try db.defaultCollection()
        
        let doc0 = createDocument(data: ["value": "a string"])
        try collection.save(document: doc0)
        
        let config = VectorIndexConfiguration(expression: "value", dimensions: 300, centroids: 8)
        try createVectorIndex(collection: collection, name: "vector_index", config: lazyConfig(config))
        
        let index = try collection.index(withName: "vector_index")!
        let updater = try index.beginUpdate(limit: 10)!
        XCTAssertEqual(updater.count, 1)
        
        expectException(exception: .rangeException) {
            _ = updater.string(at: 1)
        }
        
        expectException(exception: .rangeException) {
            _ = updater.int(at: 1)
        }
        
        expectException(exception: .rangeException) {
            _ = updater.int64(at: 1)
        }
        
        expectException(exception: .rangeException) {
            _ = updater.float(at: 1)
        }
        
        expectException(exception: .rangeException) {
            _ = updater.double(at: 1)
        }
        
        expectException(exception: .rangeException) {
            _ = updater.boolean(at: 1)
        }
        
        expectException(exception: .rangeException) {
            _ = updater.date(at: 1)
        }
        
        expectException(exception: .rangeException) {
            _ = updater.blob(at: 1)
        }
        
        expectException(exception: .rangeException) {
            _ = updater.dictionary(at: 1)
        }
        
        expectException(exception: .rangeException) {
            _ = updater.array(at: 1)
        }
        
        expectException(exception: .rangeException) {
            _ = updater.value(at: 1)
        }
        
        expectException(exception: .rangeException) {
            try! updater.setVector([1.0, 2.0, 3.0], at: 1)
        }
        
        expectException(exception: .rangeException) {
            updater.skipVector(at: 1)
        }
    }
    
    #endif
}
