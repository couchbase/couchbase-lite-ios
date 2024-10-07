//
//  VectorSearchTest+Lazy.m
//  CouchbaseLite
//
//  Copyright (c) 2024 Couchbase, Inc All rights reserved.
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
#import "VectorSearchTest.h"
#import "CBLJSON.h"

/**
 * Test Spec: https://github.com/couchbaselabs/couchbase-lite-api/blob/master/spec/tests/T0002-Lazy-Vector-Index.md
 *
 * Vesion: 2.0.1
 *
 * Test 6. TestGetIndexOnClosedDatabase is tested in CollectionTest
 * Test 7. TestGetIndexOnDeletedCollection is tested in CollectionTest
 */

#define LAZY_VECTOR_INDEX_CONFIG(E, D, C) [self lazyVectorIndexConfigWithExpression: (E) dimensions: (D) centroids: (C)]

@interface VectorSearchTest_Lazy : VectorSearchTest

@end

@implementation VectorSearchTest_Lazy

/** Override the default VectorSearch Expression */
- (NSString*) wordsQueryDefaultExpression {
    return @"word";
}

- (CBLQueryIndex*) wordsIndex {
    CBLQueryIndex* index = [self.wordsCollection indexWithName: kWordsIndexName error: nil];
    AssertNotNil(index);
    return index;
}

- (CBLVectorIndexConfiguration*) lazyVectorIndexConfigWithExpression: (NSString*)expression
                                                          dimensions: (unsigned int)dimensions
                                                           centroids: (unsigned int)centroids {
    CBLVectorIndexConfiguration* config = VECTOR_INDEX_CONFIG(expression, dimensions, centroids);
    config.isLazy = true;
    return config;
}

- (nullable NSArray<NSNumber*>*) vectorForWord: (NSString*)word collection: (CBLCollection*)collection {
    NSError* error;
    NSString* sql = [NSString stringWithFormat:@"SELECT vector FROM %@ WHERE word = '%@'", collection.name, word];
    
    CBLQuery* query = [self.wordDB createQuery: sql error: &error];
    AssertNotNil(query);

    CBLQueryResultSet* rs = [query execute: &error];
    AssertNotNil(rs);

    NSArray<NSNumber*>* vector;
    CBLQueryResult *result = [rs nextObject];
    if (result) {
        id value = [result arrayAtIndex: 0];
        if (value) {
            vector = (NSArray<NSNumber*>*)value;
        }
    }
    return vector;
}

- (nullable NSArray<NSNumber*>*) vectorForWord: (NSString*)word {
    NSArray<NSNumber*>* results = [self vectorForWord: word collection: self.wordsCollection];
    if (!results) {
        results = [self vectorForWord: word collection: self.extWordsCollection];
    }
    AssertNotNil(results);
    return results;
}

/**
 * 1. TestIsLazyDefaultValue
 * Description
 *     Test that isLazy property is false by default.
 * Steps
 *     1. Create a VectorIndexConfiguration object.
 *         - expression: "vector"
 *         - dimensions: 300
 *         - centroids: 20
 *     2.  Check that isLazy returns false.
 */
- (void) testIsLazyDefaultValue {
    CBLVectorIndexConfiguration* config = VECTOR_INDEX_CONFIG(@"vector", 300, 8);
    AssertEqual(config.isLazy, false);
}

/**
 * 2. TestIsLazyAccessor
 *
 * Description
 * Test that isLazy getter/setter of the VectorIndexConfiguration work as expected.
 *
 * Steps
 * 1. Create a VectorIndexConfiguration object.
 *    - expression: word
 *    - dimensions: 300
 *    - centroids : 20
 * 2. Set isLazy to true
 * 3. Check that isLazy returns true.
 */
- (void) testIsLazyAccessor {
    CBLVectorIndexConfiguration* config = VECTOR_INDEX_CONFIG(@"vector", 300, 8);
    config.isLazy = true;
    AssertEqual(config.isLazy, true);
}

/**
 * 3. TestGetNonExistingIndex
 *
 * Description
 * Test that getting non-existing index object by name returning null.
 *
 * Steps
 * 1. Get the default collection from a test database.
 * 2. Get a QueryIndex object from the default collection with the name as
 *   "nonexistingindex".
 * 3. Check that the result is null.
 */
- (void) testGetNonExistingIndex {
    NSError* error;
    CBLCollection* defaultCollection = [self.db defaultCollection: &error];
    AssertNil([defaultCollection indexWithName: @"nonexistingindex" error: &error]);
    AssertEqual(error.code, 0);
}

/**
 * 4. TestGetExistingNonVectorIndex
 *
 * Description
 * Test that getting non-existing index object by name returning an index object correctly.
 *
 * Steps
 * 1. Get the default collection from a test database.
 * 2. Create a value index named "value_index" in the default collection
 *   with the expression as "value".
 * 3. Get a QueryIndex object from the default collection with the name as
 *   "value_index".
 * 4. Check that the result is not null.
 * 5. Check that the QueryIndex's name is "value_index".
 * 6. Check that the QueryIndex's collection is the same instance that
 *   is used for getting the QueryIndex object.
 */
- (void) testGetExistingNonVectorIndex {
    NSError* error;
    CBLCollection* defaultCollection = [self.db defaultCollection: &error];
    
    CBLValueIndexItem* item = [CBLValueIndexItem expression:
                               [CBLQueryExpression property: @"value"]];
    CBLValueIndex* vIndex = [CBLIndexBuilder valueIndexWithItems: @[item]];
    [defaultCollection createIndex: vIndex name: @"value_index" error: &error];
    AssertNil(error);
    
    CBLQueryIndex* qIndex = [defaultCollection indexWithName: @"value_index" error: &error];
    AssertEqual(qIndex.name, @"value_index");
    AssertEqual(qIndex.collection, defaultCollection);
}

/**
 * 5. TestGetExistingVectorIndex
 *
 * Description
 * Test that getting an existing index object by name returning an index object correctly.
 *
 * Steps
 * 1. Copy database words_db.
 * 2. Create a vector index named "words_index" in the _default.words collection.
 *     - expression: "vector"
 *     - dimensions: 300
 *     - centroids : 8
 * 3. Get a QueryIndex object from the words collection with the name as "words_index".
 * 4. Check that the result is not null.
 * 5. Check that the QueryIndex's name is "words_index".
 * 6. Check that the QueryIndex's collection is the same instance that is used for
 *   getting the index.
 */
- (void) testGetExistingVectorIndex {
    [self createWordsIndexWithConfig: VECTOR_INDEX_CONFIG(@"vector", 300, 8)];
    
    CBLQueryIndex* index = [self wordsIndex];
    AssertEqual(index.name, @"words_index");
    AssertEqual(index.collection, self.wordsCollection);
}

/**
 * 8. TestLazyVectorIndexNotAutoUpdatedChangedDocs
 *
 * Description
 * Test that the lazy index is lazy. The index will not be automatically
 * updated when the documents are created or updated.
 *
 * Steps
 * 1. Copy database words_db.
 * 2. Create a vector index named "words_index" in the _default.words collection.
 *     - expression: "word"
 *     - dimensions: 300
 *     - centroids : 8
 *     - isLazy : true
 * 3. Create an SQL++ query:
 *     - SELECT word
 *       FROM _default.words
 *       ORDER BY APPROX_VECTOR_DISTANCE(word, $dinnerVector)
 *       LIMIT 10
 * 4. Execute the query and check that 0 results are returned.
 * 5. Update the documents:
 *     - Create _default.words.word301 with the content from _default.extwords.word1
 *     - Update _default.words.word1 with the content from _default.extwords.word3
 * 6. Execute the same query and check that 0 results are returned.
 */
- (void) testLazyVectorIndexNotAutoUpdatedChangedDocs {
    [self createWordsIndexWithConfig: LAZY_VECTOR_INDEX_CONFIG(@"word", 300, 8)];
    
    CBLQueryResultSet* rs = [self executeWordsQueryNoTrainingCheckWithLimit: 10];
    AssertEqual(rs.allObjects.count, 0);
    
    // Update docs:
    NSError* error;
    CBLDocument* extWord1 = [self.extWordsCollection documentWithID: @"word1" error : &error];
    CBLMutableDocument* word301 = [self createDocument: @"word301" data: [extWord1 toDictionary]];
    Assert([self.wordsCollection saveDocument: word301 error: &error]);
    
    CBLDocument* extWord3 = [self.extWordsCollection documentWithID: @"word3" error : &error];
    CBLMutableDocument* word1 = [[self.wordsCollection documentWithID: @"word1" error: &error] toMutable];
    [word1 setData: [extWord3 toDictionary]];
    Assert([self.wordsCollection saveDocument: word1 error: &error]);
    
    rs = [self executeWordsQueryNoTrainingCheckWithLimit: 10];
    AssertEqual(rs.allObjects.count, 0);
}

/**
 * 9. TestLazyVectorIndexAutoUpdateDeletedDocs
 *
 * Description
 * Test that when the lazy vector index automatically update when documents are
 * deleted.
 *
 * Steps
 * 1. Copy database words_db.
 * 2. Create a vector index named "words_index" in the _default.words collection.
 *     - expression: "word"
 *     - dimensions: 300
 *     - centroids : 8
 *     - isLazy : true
 * 3. Call beginUpdate() with limit 1 to get an IndexUpdater object.
 * 4. Check that the IndexUpdater is not null and IndexUpdater.count = 1.
 * 5. With the IndexUpdater object:
 *    - Get the word string from the IndexUpdater.
 *    - Query the vector by word from the _default.words collection.
 *    - Convert the vector result which is an array object to a platform's float array.
 *    - Call setVector() with the platform's float array at the index.
 *    - Call finish()
 * 6. Create an SQL++ query:
 *    - SELECT word
 *      FROM _default.words
 *      ORDER BY APPROX_VECTOR_DISTANCE(word, $dinnerVector)
 *      LIMIT 300
 * 7. Execute the query and check that 1 results are returned.
 * 8. Check that the word gotten from the query result is the same as the word in Step 5.
 * 9. Delete _default.words.word1 doc.
 * 10. Execute the same query as Step again and check that 0 results are returned.
 */
- (void) testLazyVectorIndexAutoUpdateDeletedDocs {
    [self createWordsIndexWithConfig: LAZY_VECTOR_INDEX_CONFIG(@"word", 300, 8)];
    
    NSError* error;
    CBLQueryIndex* index = [self wordsIndex];
    CBLIndexUpdater* updater = [index beginUpdateWithLimit: 1 error: &error];
    AssertNotNil(updater);
    AssertEqual(updater.count, 1);
    
    // Update Index:
    NSString* word = [updater stringAtIndex: 0];
    NSArray<NSNumber*>* vector = [self vectorForWord: word];
    [updater setVector: vector atIndex: 0 error: &error];
    [updater finishWithError: &error];
    AssertNil(error);
    
    // Query:
    CBLQueryResultSet* rs = [self executeWordsQueryNoTrainingCheckWithLimit: 300];
    AssertEqual(rs.allObjects.count, 1);
    
    // Delete doc and requery:
    [self.wordsCollection deleteDocument: [self.wordsCollection documentWithID: @"word1" error: &error] error: &error];
    rs = [self executeWordsQueryNoTrainingCheckWithLimit: 300];
    AssertEqual(rs.allObjects.count, 0);
}

/**
 * 10. TestLazyVectorIndexAutoUpdatePurgedDocs
 *
 * Description
 * Test that when the lazy vector index automatically update when documents are
 * purged.
 *
 * Steps
 * 1. Copy database words_db.
 * 2. Create a vector index named "words_index" in the _default.words collection.
 *     - expression: "word"
 *     - dimensions: 300
 *     - centroids : 8
 *     - isLazy : true
 * 3. Call beginUpdate() with limit 1 to get an IndexUpdater object.
 * 4. Check that the IndexUpdater is not null and IndexUpdater.count = 1.
 * 5. With the IndexUpdater object:
 *    - Get the word string from the IndexUpdater.
 *    - Query the vector by word from the _default.words collection.
 *    - Convert the vector result which is an array object to a platform's float array.
 *    - Call setVector() with the platform's float array at the index.
 * 6. With the IndexUpdater object, call finish()
 * 7. Create an SQL++ query:
 *    - SELECT word
 *      FROM _default.words
 *      ORDER BY APPROX_VECTOR_DISTANCE(word, $dinnerVector)
 *      LIMIT 300
 * 8. Execute the query and check that 1 results are returned.
 * 9. Check that the word gotten from the query result is the same as the word in Step 5.
 * 10. Purge _default.words.word1 doc.
 * 11. Execute the same query as Step again and check that 0 results are returned.
 */
- (void) testLazyVectorIndexAutoUpdatePurgedDocs {
    [self createWordsIndexWithConfig: LAZY_VECTOR_INDEX_CONFIG(@"word", 300, 8)];
    
    NSError* error;
    CBLQueryIndex* index = [self wordsIndex];
    CBLIndexUpdater* updater = [index beginUpdateWithLimit: 1 error: &error];
    AssertNotNil(updater);
    AssertEqual(updater.count, 1);
    
    // Update Index:
    NSString* word = [updater stringAtIndex: 0];
    NSArray<NSNumber*>* vector = [self vectorForWord: word];
    [updater setVector: vector atIndex: 0 error: &error];
    [updater finishWithError: &error];
    AssertNil(error);
    
    // Query:
    CBLQueryResultSet* rs = [self executeWordsQueryNoTrainingCheckWithLimit: 300];
    AssertEqual(rs.allObjects.count, 1);
    
    // Delete doc and requery:
    [self.wordsCollection purgeDocumentWithID: @"word1" error: &error];
    rs = [self executeWordsQueryNoTrainingCheckWithLimit: 300];
    AssertEqual(rs.allObjects.count, 0);
}

/**
 * 11. TestIndexUpdaterBeginUpdateOnNonVectorIndex
 *
 * Description
 * Test that a CouchbaseLiteException is thrown when calling beginUpdate on
 * a non vector index.
 *
 * Steps
 * 1. Get the default collection from a test database.
 * 2. Create a value index named "value_index" in the default collection with the
 *   expression as "value".
 * 3. Get a QueryIndex object from the default collection with the name as
 *   "value_index".
 * 4. Call beginUpdate() with limit 10 on the QueryIndex object.
 * 5. Check that a CouchbaseLiteException with the code Unsupported is thrown.
 */
- (void) testIndexUpdaterBeginUpdateOnNonVectorIndex {
    NSError* error;
    CBLCollection* defaultCollection = [self.db defaultCollection: &error];
    AssertNil(error);
    
    CBLValueIndexItem* item = [CBLValueIndexItem expression:
                               [CBLQueryExpression property: @"value"]];
    CBLValueIndex* vIndex = [CBLIndexBuilder valueIndexWithItems: @[item]];
    [defaultCollection createIndex: vIndex name: @"value_index" error: &error];
    
    AssertNil(error);
    
    CBLQueryIndex* qIndex = [defaultCollection indexWithName: @"value_index" error: &error];
    
    [self expectError: CBLErrorDomain code: CBLErrorUnsupported in: ^BOOL(NSError** err) {
        return [qIndex beginUpdateWithLimit: 10 error: err] != nil;
    }];
}

/**
 * 12. TestIndexUpdaterBeginUpdateOnNonLazyVectorIndex
 *
 * Description
 * Test that a CouchbaseLiteException is thrown when calling beginUpdate
 * on a non lazy vector index.
 *
 * Steps
 * 1. Copy database words_db.
 * 2. Create a vector index named "words_index" in the _default.words collection.
 *     - expression: "word"
 *     - dimensions: 300
 *     - centroids : 8
 * 3. Get a QueryIndex object from the words collection with the name as
 *   "words_index".
 * 4. Call beginUpdate() with limit 10 on the QueryIndex object.
 * 5. Check that a CouchbaseLiteException with the code Unsupported is thrown.
 */
- (void) testIndexUpdaterBeginUpdateOnNonLazyVectorIndex {
    [self createWordsIndexWithConfig: VECTOR_INDEX_CONFIG(@"vector", 300, 8)];
    
    CBLQueryIndex* index = [self wordsIndex];
    [self expectError: CBLErrorDomain code: CBLErrorUnsupported in: ^BOOL(NSError** err) {
        return [index beginUpdateWithLimit: 10 error: err] != nil;
    }];
}

/**
 * 13. TestIndexUpdaterBeginUpdateWithZeroLimit
 *
 * Description
 * Test that an InvalidArgument exception is returned when calling beginUpdate
 * with zero limit.
 *
 * Steps
 * 1. Copy database words_db.
 * 2. Create a vector index named "words_index" in
 *     - expression: "word"
 *     - dimensions: 300
 *     - centroids : 8
 *     - isLazy : true
 * 3. Get a QueryIndex object from the words collec
 *    "words_index".
 * 4. Call beginUpdate() with limit 0 on the QueryIndex object.
 * 5. Check that an InvalidArgumentException is thrown.
 */
- (void) testIndexUpdaterBeginUpdateWithZeroLimit {
    [self createWordsIndexWithConfig: LAZY_VECTOR_INDEX_CONFIG(@"word", 300, 8)];
    
    CBLQueryIndex* index = [self wordsIndex];
    
    [self expectException: @"NSInvalidArgumentException" in: ^{
        [index beginUpdateWithLimit: 0 error: nil];
    }];
}

/**
 * 14. TestIndexUpdaterBeginUpdateOnLazyVectorIndex
 *
 * Description
 * Test that calling beginUpdate on a lazy vector index returns an IndexUpdater.
 *
 * Steps
 * 1. Copy database words_db.
 * 2. Create a vector index named "words_index" in the _default.words collection.
 *     - expression: "word"
 *     - dimensions: 300
 *     - centroids : 8
 *     - isLazy : true
 * 3. Get a QueryIndex object from the words with the name as "words_index".
 * 4. Call beginUpdate() with limit 10 on the QueryIndex object.
 * 5. Check that the returned IndexUpdater is not null.
 * 6. Check that the IndexUpdater.count is 10.
 */
- (void) testIndexUpdaterBeginUpdateOnLazyVectorIndex {
    [self createWordsIndexWithConfig: LAZY_VECTOR_INDEX_CONFIG(@"word", 300, 8)];
    
    NSError* error;
    CBLQueryIndex* index = [self wordsIndex];
    CBLIndexUpdater* updater = [index beginUpdateWithLimit: 10 error: &error];
    AssertNotNil(updater);
    AssertEqual(updater.count, 10);
}

/**
 * 15. TestIndexUpdaterGettingValues
 *
 * Description
 * Test all type getters and toArary() from the Array interface. The test
 * may be divided this test into multiple tests per type getter as appropriate.
 *
 * Steps
 * 1. Get the default collection from a test database.
 * 2. Create the followings documents:
 *     - doc-0 : { "value": "a string" }
 *     - doc-1 : { "value": 100 }
 *     - doc-2 : { "value": 20.8 }
 *     - doc-3 : { "value": true }
 *     - doc-4 : { "value": false }
 *     - doc-5 : { "value": Date("2024-05-10T00:00:00.000Z") }
 *     - doc-6 : { "value": Blob(Data("I'm Bob")) }
 *     - doc-7 : { "value": {"name": "Bob"} }
 *     - doc-8 : { "value": ["one", "two", "three"] }
 *     - doc-9 : { "value": null }
 * 3. Create a vector index named "vector_index" in the default collection.
 *     - expression: "value"
 *     - dimensions: 300
 *     - centroids : 8
 *     - isLazy : true
 * 4. Get a QueryIndex object from the default collection with the name as
 *    "vector_index".
 * 5. Call beginUpdate() with limit 10 to get an IndexUpdater object.
 * 6. Check that the IndexUpdater.count is 10.
 * 7. Get string value from each index and check the followings:
 *     - getString(0) : value == "a string"
 *     - getString(1) : value == null
 *     - getString(2) : value == null
 *     - getString(3) : value == null
 *     - getString(4) : value == null
 *     - getString(5) : value == "2024-05-10T00:00:00.000Z"
 *     - getString(6) : value == null
 *     - getString(7) : value == null
 *     - getString(8) : value == null
 *     - getString(9) : value == null
 * 8. Get integer value from each index and check the followings:
 *     - getInt(0) : value == 0
 *     - getInt(1) : value == 100
 *     - getInt(2) : value == 20
 *     - getInt(3) : value == 1
 *     - getInt(4) : value == 0
 *     - getInt(5) : value == 0
 *     - getInt(6) : value == 0
 *     - getInt(7) : value == 0
 *     - getInt(8) : value == 0
 *     - getInt(9) : value == 0
 * 9. Get float value from each index and check the followings:
 *     - getFloat(0) : value == 0.0
 *     - getFloat(1) : value == 100.0
 *     - getFloat(2) : value == 20.8
 *     - getFloat(3) : value == 1.0
 *     - getFloat(4) : value == 0.0
 *     - getFloat(5) : value == 0.0
 *     - getFloat(6) : value == 0.0
 *     - getFloat(7) : value == 0.0
 *     - getFloat(8) : value == 0.0
 *     - getFloat(9) : value == 0.0
 * 10. Get double value from each index and check the followings:
 *     - getDouble(0) : value == 0.0
 *     - getDouble(1) : value == 100.0
 *     - getDouble(2) : value == 20.8
 *     - getDouble(3) : value == 1.0
 *     - getDouble(4) : value == 0.0
 *     - getDouble(5) : value == 0.0
 *     - getDouble(6) : value == 0.0
 *     - getDouble(7) : value == 0.0
 *     - getDouble(8) : value == 0.0
 *     - getDouble(9) : value == 0.0
 * 11. Get boolean value from each index and check the followings:
 *     - getBoolean(0) : value == true
 *     - getBoolean(1) : value == true
 *     - getBoolean(2) : value == true
 *     - getBoolean(3) : value == true
 *     - getBoolean(4) : value == false
 *     - getBoolean(5) : value == true
 *     - getBoolean(6) : value == true
 *     - getBoolean(7) : value == true
 *     - getBoolean(8) : value == true
 *     - getBoolean(9) : value == false
 * 12. Get date value from each index and check the followings:
 *     - getDate(0) : value == "2024-05-10T00:00:00.000Z"
 *     - getDate(1) : value == null
 *     - getDate(2) : value == null
 *     - getDate(3) : value == null
 *     - getDate(4) : value == null
 *     - getDate(5) : value == Date("2024-05-10T00:00:00.000Z")
 *     - getDate(6) : value == null
 *     - getDate(7) : value == null
 *     - getDate(8) : value == null
 *     - getDate(9) : value == null
 * 13. Get blob value from each index and check the followings:
 *     - getBlob(0) : value == null
 *     - getBlob(1) : value == null
 *     - getBlob(2) : value == null
 *     - getBlob(3) : value == null
 *     - getBlob(4) : value == null
 *     - getBlob(5) : value == null
 *     - getBlob(6) : value == Blob(Data("I'm Bob"))
 *     - getBlob(7) : value == null
 *     - getBlob(8) : value == null
 *     - getBlob(9) : value == null
 * 14. Get dictionary object from each index and check the followings:
 *     - getDictionary(0) : value == null
 *     - getDictionary(1) : value == null
 *     - getDictionary(2) : value == null
 *     - getDictionary(3) : value == null
 *     - getDictionary(4) : value == null
 *     - getDictionary(5) : value == null
 *     - getDictionary(6) : value == null
 *     - getDictionary(7) : value == Dictionary({"name": "Bob"})
 *     - getDictionary(8) : value == null
 *     - getDictionary(9) : value == null
 * 15. Get array object from each index and check the followings:
 *     - getArray(0) : value == null
 *     - getArray(1) : value == null
 *     - getArray(2) : value == null
 *     - getArray(3) : value == null
 *     - getArray(4) : value == null
 *     - getArray(5) : value == null
 *     - getArray(6) : value == null
 *     - getArray(7) : value == null
 *     - getArray(8) : value == Array(["one", "two", "three"])
 *     - getArray(9) : value == null
 * 16. Get value from each index and check the followings:
 *     - getValue(0) : value == "a string"
 *     - getValue(1) : value == PlatformNumber(100)
 *     - getValue(2) : value == PlatformNumber(20.8)
 *     - getValue(3) : value == PlatformBoolean(true)
 *     - getValue(4) : value == PlatformBoolean(false)
 *     - getValue(5) : value == Date("2024-05-10T00:00:00.000Z")
 *     - getValue(6) : value == Blob(Data("I'm Bob"))
 *     - getValue(7) : value == Dictionary({"name": "Bob"})
 *     - getValue(8) : value == Array(["one", "two", "three"])
 *     - getValue(9) : value == null
 * 17. Get IndexUodater values as a platform array by calling toArray() and check
 *     that the array contains all values as expected.
 */
- (void) testIndexUpdaterGettingValues {
    NSError* error;
    CBLCollection* defaultCollection = [self.db defaultCollection: &error];
    
    CBLMutableDocument* mdoc = [self createDocument: @"doc-0"];
    [mdoc setValue: @"a string" forKey: @"value"];
    [defaultCollection saveDocument: mdoc error: &error];
    
    mdoc = [self createDocument: @"doc-1"];
    [mdoc setValue: @(100) forKey: @"value"];
    [defaultCollection saveDocument: mdoc error: &error];
    
    mdoc = [self createDocument: @"doc-2"];
    [mdoc setValue: @(20.8) forKey: @"value"];
    [defaultCollection saveDocument: mdoc error: &error];
    
    mdoc = [self createDocument: @"doc-3"];
    [mdoc setValue: @(true) forKey: @"value"];
    [defaultCollection saveDocument: mdoc error: &error];
    
    mdoc = [self createDocument: @"doc-4"];
    [mdoc setValue: @(false) forKey: @"value"];
    [defaultCollection saveDocument: mdoc error: &error];
    
    mdoc = [self createDocument: @"doc-5"];
    [mdoc setValue: [CBLJSON dateWithJSONObject: @"2024-05-10T00:00:00.000Z"] forKey: @"value"];
    [defaultCollection saveDocument: mdoc error: &error];
    
    mdoc = [self createDocument: @"doc-6"];
    NSData* content = [@"I'm Blob" dataUsingEncoding: NSUTF8StringEncoding];
    CBLBlob* blob = [[CBLBlob alloc] initWithContentType:@"text/plain" data: content];
    [mdoc setValue: blob forKey: @"value"];
    [defaultCollection saveDocument: mdoc error: &error];
    
    mdoc = [self createDocument: @"doc-7"];
    CBLMutableDictionary* dict = [[CBLMutableDictionary alloc] init];
    [dict setValue: @"Bob" forKey: @"name"];
    [mdoc setValue: dict forKey: @"value"];
    [defaultCollection saveDocument: mdoc error: &error];
    
    mdoc = [self createDocument: @"doc-8"];
    CBLMutableArray* array = [[CBLMutableArray alloc] init];
    [array addValue: @"one"];
    [array addValue: @"two"];
    [array addValue: @"three"];
    [mdoc setValue: array forKey: @"value"];
    [defaultCollection saveDocument: mdoc error: &error];
    
    mdoc = [self createDocument: @"doc-9"];
    [mdoc setValue: [NSNull null] forKey: @"value"];
    [defaultCollection saveDocument: mdoc error: &error];
    
    // Create index
    [self createVectorIndexInCollection: defaultCollection
                                   name: @"vector_index"
                                 config: LAZY_VECTOR_INDEX_CONFIG(@"value", 300, 8)];
    
    CBLQueryIndex* index = [defaultCollection indexWithName: @"vector_index" error: &error];
    AssertNotNil(index);
    
    CBLIndexUpdater* updater = [index beginUpdateWithLimit: 10 error: &error];
    AssertEqual(updater.count, 10);
    
    // String getter
    Assert([[updater stringAtIndex: 0] isEqual: @"a string"]);
    AssertEqual([updater stringAtIndex: 1], nil);
    AssertEqual([updater stringAtIndex: 2], nil);
    AssertEqual([updater stringAtIndex: 3], nil);
    AssertEqual([updater stringAtIndex: 4], nil);
    Assert([[updater stringAtIndex: 5] isEqual: @"2024-05-10T00:00:00.000Z"]);
    AssertEqual([updater stringAtIndex: 6], nil);
    AssertEqual([updater stringAtIndex: 7], nil);
    AssertEqual([updater stringAtIndex: 8], nil);
    AssertEqual([updater stringAtIndex: 9], nil);
    
    // Int getter
    AssertEqual([updater integerAtIndex: 0], 0);
    AssertEqual([updater integerAtIndex: 1], 100);
    AssertEqual([updater integerAtIndex: 2], 20);
    AssertEqual([updater integerAtIndex: 3], 1);
    AssertEqual([updater integerAtIndex: 4], 0);
    AssertEqual([updater integerAtIndex: 5], 0);
    AssertEqual([updater integerAtIndex: 6], 0);
    AssertEqual([updater integerAtIndex: 7], 0);
    AssertEqual([updater integerAtIndex: 8], 0);
    AssertEqual([updater integerAtIndex: 9], 0);
    
    // Float getter
    AssertEqual([updater floatAtIndex: 0], 0.0);
    AssertEqual([updater floatAtIndex: 1], 100.0);
    AssertEqual([updater floatAtIndex: 2], (float)20.8);
    AssertEqual([updater floatAtIndex: 3], 1.0);
    AssertEqual([updater floatAtIndex: 4], 0.0);
    AssertEqual([updater floatAtIndex: 5], 0.0);
    AssertEqual([updater floatAtIndex: 6], 0.0);
    AssertEqual([updater floatAtIndex: 7], 0.0);
    AssertEqual([updater floatAtIndex: 8], 0.0);
    AssertEqual([updater floatAtIndex: 9], 0.0);
    
    // Double getter
    AssertEqual([updater doubleAtIndex: 0], 0.0);
    AssertEqual([updater doubleAtIndex: 1], 100.0);
    AssertEqual([updater doubleAtIndex: 2], 20.8);
    AssertEqual([updater doubleAtIndex: 3], 1.0);
    AssertEqual([updater doubleAtIndex: 4], 0.0);
    AssertEqual([updater doubleAtIndex: 5], 0.0);
    AssertEqual([updater doubleAtIndex: 6], 0.0);
    AssertEqual([updater doubleAtIndex: 7], 0.0);
    AssertEqual([updater doubleAtIndex: 8], 0.0);
    AssertEqual([updater doubleAtIndex: 9], 0.0);
    
    // Boolean getter
    AssertEqual([updater booleanAtIndex: 0], true);
    AssertEqual([updater booleanAtIndex: 1], true);
    AssertEqual([updater booleanAtIndex: 2], true);
    AssertEqual([updater booleanAtIndex: 3], true);
    AssertEqual([updater booleanAtIndex: 4], false);
    AssertEqual([updater booleanAtIndex: 5], true);
    AssertEqual([updater booleanAtIndex: 6], true);
    AssertEqual([updater booleanAtIndex: 7], true);
    AssertEqual([updater booleanAtIndex: 8], true);
    AssertEqual([updater booleanAtIndex: 9], false);
    
    // Date getter
    AssertEqual([updater dateAtIndex: 0], nil);
    AssertEqual([updater dateAtIndex: 1], nil);
    AssertEqual([updater dateAtIndex: 2], nil);
    AssertEqual([updater dateAtIndex: 3], nil);
    AssertEqual([updater dateAtIndex: 4], nil);
    Assert([[updater dateAtIndex: 5] isEqual: [CBLJSON dateWithJSONObject: @"2024-05-10T00:00:00.000Z"]]);
    AssertEqual([updater dateAtIndex: 6], nil);
    AssertEqual([updater dateAtIndex: 7], nil);
    AssertEqual([updater dateAtIndex: 8], nil);
    AssertEqual([updater dateAtIndex: 9], nil);
    
    // Blob getter
    AssertEqual([updater blobAtIndex: 0], nil);
    AssertEqual([updater blobAtIndex: 1], nil);
    AssertEqual([updater blobAtIndex: 2], nil);
    AssertEqual([updater blobAtIndex: 3], nil);
    AssertEqual([updater blobAtIndex: 4], nil);
    AssertEqual([updater blobAtIndex: 5], nil);
    Assert([[updater blobAtIndex: 6] isEqual: blob]);
    AssertEqual([updater blobAtIndex: 7], nil);
    AssertEqual([updater blobAtIndex: 8], nil);
    AssertEqual([updater blobAtIndex: 9], nil);
    
    // Dict getter
    AssertEqual([updater dictionaryAtIndex: 0], nil);
    AssertEqual([updater dictionaryAtIndex: 1], nil);
    AssertEqual([updater dictionaryAtIndex: 2], nil);
    AssertEqual([updater dictionaryAtIndex: 3], nil);
    AssertEqual([updater dictionaryAtIndex: 4], nil);
    AssertEqual([updater dictionaryAtIndex: 5], nil);
    AssertEqual([updater dictionaryAtIndex: 6], nil);
    Assert([[updater dictionaryAtIndex: 7] isEqual: dict]);
    AssertEqual([updater dictionaryAtIndex: 8], nil);
    AssertEqual([updater dictionaryAtIndex: 9], nil);
    
    // Array getter
    AssertEqual([updater arrayAtIndex: 0], nil);
    AssertEqual([updater arrayAtIndex: 1], nil);
    AssertEqual([updater arrayAtIndex: 2], nil);
    AssertEqual([updater arrayAtIndex: 3], nil);
    AssertEqual([updater arrayAtIndex: 4], nil);
    AssertEqual([updater arrayAtIndex: 5], nil);
    AssertEqual([updater arrayAtIndex: 6], nil);
    AssertEqual([updater arrayAtIndex: 7], nil);
    Assert([[updater arrayAtIndex: 8] isEqual: array]);
    AssertEqual([updater arrayAtIndex: 9], nil);
    
    // Value getter
    Assert([[updater valueAtIndex: 0] isEqual: @"a string"]);
    Assert([[updater valueAtIndex: 1] isEqual: @(100)]);
    Assert([[updater valueAtIndex: 2] isEqual: @(20.8)]);
    Assert([[updater valueAtIndex: 3] isEqual: @(true)]);
    Assert([[updater valueAtIndex: 4] isEqual: @(false)]);
    Assert([[updater valueAtIndex: 5] isEqual: @"2024-05-10T00:00:00.000Z"]);
    Assert([[updater valueAtIndex: 6] isEqual: blob]);
    Assert([[updater valueAtIndex: 7] isEqual: dict]);
    Assert([[updater valueAtIndex: 8] isEqual: array]);
    Assert([[updater valueAtIndex: 9] isEqual: [NSNull null]]);
    
    NSArray* expected = @[@"a string", @(100), @(20.8), @(true), @(false), @"2024-05-10T00:00:00.000Z", blob,
                           [dict toDictionary], [array toArray], [NSNull null]];
    NSArray* updaterArray = [updater toArray];
    for (NSUInteger i = 0; i < expected.count; i++) {
        AssertEqualObjects(updaterArray[i], expected[i]);
    }
}

/**
 * 17. TestIndexUpdaterSetFloatArrayVectors
 *
 * Description
 * Test that setting float array vectors works as expected.
 *
 * Steps
 * 1. Copy database words_db.
 * 2. Create a vector index named "words_index" in the _default.words collection.
 *     - expression: "word"
 *     - dimensions: 300
 *     - centroids : 8
 *     - isLazy : true
 * 3. Get a QueryIndex object from the words with the name as "words_index".
 * 4. Call beginUpdate() with limit 10 to get an IndexUpdater object.
 * 5. With the IndexUpdater object, for each index from 0 to 9.
 *     - Get the word string from the IndexUpdater and store the word string in a set for verifying
 *        the vector search result.
 *     - Query the vector by word from the _default.words collection.
 *     - Convert the vector result which is an array object to a platform's float array.
 *     - Call setVector() with the platform's float array at the index.
 * 6. With the IndexUpdater object, call finish()
 * 7. Execute a vector search query.
 *     - SELECT word
 *       FROM _default.words
 *       ORDER BY APPROX_VECTOR_DISTANCE(word, $dinnerVector)
 *       LIMIT 300
 * 8. Check that there are 10 words returned.
 * 9. Check that the word is in the word set from the step 5.
 */

- (void) testIndexUpdaterSetFloatArrayVectors {
    [self createWordsIndexWithConfig: LAZY_VECTOR_INDEX_CONFIG(@"word", 300, 8)];
    
    NSError* error;
    CBLQueryIndex* index = [self wordsIndex];
    CBLIndexUpdater* updater = [index beginUpdateWithLimit: 10 error: &error];
    AssertNotNil(updater);
    AssertEqual(updater.count, 10);
    
    // Update Index:
    NSMutableArray<NSString*>* indexedWords = [NSMutableArray array];
    for(NSUInteger i = 0; i < updater.count; i++) {
        NSString* word = [updater stringAtIndex: i];
        NSArray<NSNumber*>* vector = [self vectorForWord: word];
        Assert([updater setVector: vector atIndex: i error: &error]);
        [indexedWords addObject: word];
    }
    
    Assert([updater finishWithError: &error]);
    
    CBLQueryResultSet* rs = [self executeWordsQueryNoTrainingCheckWithLimit: 300];
    NSDictionary<NSString*, NSString*>* wordMap = [self toDocIDWordMap: rs];
    AssertEqual(wordMap.count, 10);
    
    NSArray<NSString*>* words = [wordMap allValues];
    for(NSString* word in words) {
        Assert([indexedWords containsObject: word]);
    }
}

/**
 * 20. TestIndexUpdaterSetInvalidVectorDimensions
 *
 * Description
 * Test thta the vector with the invalid dimenions different from the dimensions
 * set to the configuration will not be included in the index.
 *
 * Steps
 * 1. Copy database words_db.
 * 2. Create a vector index named "words_index" in the _default.words collection.
 *     - expression: "word"
 *     - dimensions: 300
 *     - centroids : 8
 *     - isLazy : true
 * 3. Get a QueryIndex object from the words with the name as "words_index".
 * 4. Call beginUpdate() with limit 1 to get an IndexUpdater object.
 * 5. With the IndexUpdater object, call setVector() with a float array as [1.0]
 * 6. Check that the setVector throws CouchbaseLiteException with the InvalidParameter error.
 */
- (void) testIndexUpdaterSetInvalidVectorDimensions {
    [self createWordsIndexWithConfig: LAZY_VECTOR_INDEX_CONFIG(@"word", 300, 8)];
    
    NSError* error;
    CBLQueryIndex* index = [self wordsIndex];
    CBLIndexUpdater* updater = [index beginUpdateWithLimit: 1 error: &error];
    AssertNotNil(updater);
    AssertEqual(updater.count, 1);
    
    [self expectError: CBLErrorDomain code: CBLErrorInvalidParameter in: ^BOOL(NSError** err) {
        return [updater setVector: @[@1.0] atIndex: 0 error: err];
    }];
}

/**
 * 21. TestIndexUpdaterSkipVectors
 *
 * Description
 * Test that skipping vectors works as expected.
 *
 * Steps
 * 1. Copy database words_db.
 * 2. Create a vector index named "words_index" in the _default.words collection.
 *     - expression: "word"
 *     - dimensions: 300
 *     - centroids : 8
 *     - isLazy : true
 * 3. Get a QueryIndex object from the words with the name as "words_index".
 * 4. Call beginUpdate() with limit 10 to get an IndexUpdater object.
 * 5. With the IndexUpdater object, for each index from 0 - 9.
 *     - Get the word string from the IndexUpdater.
 *     - If index % 2 == 0,
 *         - Store the word string in a skipped word set for verifying the skipped words later.
 *         - Call skipVector at the index.
 *     - If index % 2 != 0,
 *         - Query the vector by word from the _default.words collection.
 *         - Convert the vector result which is an array object to a platform's float array.
 *         - Call setVector() with the platform's float array at the index.
 * 6. With the IndexUpdater object, call finish()
 * 7. Call beginUpdate with limit 10 to get an IndexUpdater object.
 * 8. With the IndexUpdater object, for each index
 *     - Get the word string from the dictionary for the key named "word".
 *     - Check if the word is in the skipped word set from the Step 5. If the word
 *        is in the skipped word set, remove the word from the skipped word set.
 *     - Query the vector by word from the _default.words collection.
 *         - Convert the vector result which is an array object to a platform's float array.
 *         - Call setVector() with the platform's float array at the index
 * 9. With the IndexUpdater object, call finish()
 * 10. Repeat Step 7, until the returned IndexUpdater is null or the skipped word set
 *      has zero words in it.
 * 11. Verify that the skipped word set has zero words in it.
 */
- (void) _testIndexUpdaterSkipVectors {
    [self createWordsIndexWithConfig: LAZY_VECTOR_INDEX_CONFIG(@"word", 300, 8)];
    
    NSError* error;
    CBLQueryIndex* index = [self wordsIndex];
    CBLIndexUpdater* updater = [index beginUpdateWithLimit: 10 error: &error];
    AssertNotNil(updater);
    AssertEqual(updater.count, 10);
    
    // Update Index:
    NSMutableArray<NSString*>* skippedWords = [NSMutableArray array];
    NSMutableArray<NSString*>* indexedWords = [NSMutableArray array];
    for(NSUInteger i = 0; i < updater.count; i++) {
        NSString* word = [updater stringAtIndex: i];
        if (i % 2 == 0) {
            [skippedWords addObject: word];
            [updater skipVectorAtIndex: i];
        } else {
            [indexedWords addObject: word];
            NSArray<NSNumber*>* vector = [self vectorForWord: word];
            [updater setVector: vector atIndex: i error: &error];
        }
    }
    [updater finishWithError: &error];
    AssertNil(error);
    AssertEqual(skippedWords.count, 5);
    AssertEqual(indexedWords.count, 5);
   
    // Update index for the skipped words:
    updater = [index beginUpdateWithLimit: 10 error: &error];
    for (NSUInteger i = 0; i < updater.count; i++) {
        NSString* word = [updater stringAtIndex: i];
        [skippedWords removeObject: word];
    }
    AssertEqual(skippedWords.count, 0);
}

/**
 * 22. TestIndexUpdaterFinishWithIncompletedUpdate
 *
 * Description
 * Test that a CouchbaseLiteException is thrown when calling finish() on
 * an IndexUpdater that has incomplete updated.
 *
 * Steps
 * 1. Copy database words_db.
 * 2. Create a vector index named "words_index" in the _default.words collection.
 *     - expression: "word"
 *     - dimensions: 300
 *     - centroids : 8
 *     - isLazy : true
 * 3. Get a QueryIndex object from the words with the name as "words_index".
 * 4. Call beginUpdate() with limit 2 to get an IndexUpdater object.
 * 5. With the IndexUpdater object, call finish().
 * 6. Check that a CouchbaseLiteException with code UnsupportedOperation is thrown.
 * 7. For the index 0,
 *     - Get the word string from the IndexUpdater.
 *     - Query the vector by word from the _default.words collection.
 *     - Convert the vector result which is an array object to a platform's float array.
 *     - Call setVector() with the platform's float array at the index.
 * 8. With the IndexUpdater object, call finish().
 * 9. Check that a CouchbaseLiteException with code UnsupportedOperation is thrown.
 */
- (void) testIndexUpdaterFinishWithIncompletedUpdate {
    [self createWordsIndexWithConfig: LAZY_VECTOR_INDEX_CONFIG(@"word", 300, 10)];

    NSError* error;
    CBLQueryIndex* index = [self wordsIndex];
    CBLIndexUpdater* updater = [index beginUpdateWithLimit: 2 error: &error];
    AssertNotNil(updater);
    AssertEqual(updater.count, 2);
    
    [self expectError: CBLErrorDomain code: CBLErrorUnsupported in: ^BOOL(NSError** err) {
        return [updater finishWithError: err];
    }];
    
    NSString* word = [updater stringAtIndex: 0];
    NSArray<NSNumber*>* vector = [self vectorForWord: word];
    [updater setVector: vector atIndex: 0 error: &error];
    [self expectError: CBLErrorDomain code: CBLErrorUnsupported in: ^BOOL(NSError** err) {
        return [updater finishWithError: err];
    }];
}

/**
 * 23. TestIndexUpdaterCaughtUp
 *
 * Description
 * Test that when the lazy vector index is caught up, calling beginUpdate() to
 * get an IndexUpdater will return null.
 *
 * Steps
 * 1. Copy database words_db.
 * 2. Create a vector index named "words_index" in the _default.words collection.
 *     - expression: "word"
 *     - dimensions: 300
 *     - centroids : 8
 *     - isLazy : true
 * 3. Call beginUpdate() with limit 100 to get an IndexUpdater object.
 *     - Get the word string from the IndexUpdater.
 *     - Query the vector by word from the _default.words collection.
 *     - Convert the vector result which is an array object to a platform's float array.
 *     - Call setVector() with the platform's float array at the index.
 * 4. Repeat Step 3 two more times.
 * 5. Call beginUpdate() with limit 100 to get an IndexUpdater object.
 * 6. Check that the returned IndexUpdater is null.
 */
- (void) testIndexUpdaterCaughtUp {
    [self createWordsIndexWithConfig: LAZY_VECTOR_INDEX_CONFIG(@"word", 300, 10)];
    
    NSError* error;
    CBLQueryIndex* index = [self wordsIndex];
    
    for (NSUInteger i = 0; i < 3; i++) {
        CBLIndexUpdater* updater = [index beginUpdateWithLimit: 100 error: &error];
        AssertNotNil(updater);
        
        for(NSUInteger j = 0; j < updater.count; j++) {
            NSString* word = [updater stringAtIndex: j];
            NSArray<NSNumber*>* vector = [self vectorForWord: word];
            Assert([updater setVector: vector atIndex: j error: &error]);
        }
        Assert([updater finishWithError: &error]);
    }
    
    AssertNil([index beginUpdateWithLimit: 100 error: &error]);
    AssertEqual(error.code, 0);
}

/**
 * 24. TestNonFinishedIndexUpdaterNotUpdateIndex
 *
 * Description
 * Test that the index updater can be released without calling finish(),
 * and the released non-finished index updater doesn't update the index.
 *
 * Steps
 * 1. Copy database words_db.
 * 2. Create a vector index named "words_index" in the _default.words collection.
 *     - expression: "word"
 *     - dimensions: 300
 *     - centroids : 8
 *     - isLazy : true
 * 3. Get a QueryIndex object from the words with the name as "words_index".
 * 4. Call beginUpdate() with limit 10 to get an IndexUpdater object.
 * 5. With the IndexUpdater object, for each index from 0 - 9.
 *     - Get the word string from the IndexUpdater.
 *     - Query the vector by word from the _default.words collection.
 *     - Convert the vector result which is an array object to a platform's float array.
 *     - Call setVector() with the platform's float array at the index.
 * 6. Release or close the index updater object.
 * 7. Execute a vector search query.
 *     - SELECT word
 *       FROM _default.words
 *       ORDER BY APPROX_VECTOR_DISTANCE(word, $dinnerVector)
 *       LIMIT 300
 * 8. Check that there are 0 words returned.
 */
- (void) testNonFinishedIndexUpdaterNotUpdateIndex {
    [self createWordsIndexWithConfig: LAZY_VECTOR_INDEX_CONFIG(@"word", 300, 8)];
    
    NSError* error;
    CBLQueryIndex* index = [self wordsIndex];
    CBLIndexUpdater* updater = [index beginUpdateWithLimit: 10 error: &error];
    AssertNotNil(updater);
    AssertEqual(updater.count, 10);
    
    // Update index:
    for(NSUInteger i = 0; i < updater.count; i++) {
        NSString* word = [updater stringAtIndex: i];
        NSArray<NSNumber*>* vector = [self vectorForWord: word];
        Assert([updater setVector: vector atIndex: i error: &error]);
    }
    
    // "Release" CBLIndexUpdater
    updater = nil;
    CBLQueryResultSet* rs = [self executeWordsQueryNoTrainingCheckWithLimit: 300];
    AssertEqual(rs.allObjects.count, 0);
}

/**
 * 25. TestIndexUpdaterIndexOutOfBounds
 *
 * Description
 * Test that when using getter, setter, and skip function with the index that
 * is out of bounds, an IndexOutOfBounds or InvalidArgument exception
 * is throws.
 *
 * Steps
 * 1. Get the default collection from a test database.
 * 2. Create the followings documents:
 *     - doc-0 : { "value": "a string" }
 * 3. Create a vector index named "vector_index" in the default collection.
 *     - expression: "value"
 *     - dimensions: 3
 *     - centroids : 8
 *     - isLazy : true
 * 4. Get a QueryIndex object from the default collection with the name as
 *    "vector_index".
 * 5. Call beginUpdate() with limit 10 to get an IndexUpdater object.
 * 6. Check that the IndexUpdater.count is 1.
 * 7. Call each getter function with index = -1 and check that
 *    an IndexOutOfBounds or InvalidArgument exception is thrown.
 * 8. Call each getter function with index = 1 and check that
 *    an IndexOutOfBounds or InvalidArgument exception is thrown.
 * 9. Call setVector() function with a vector = [1.0, 2.0, 3.0] and index = -1 and check that
 *    an IndexOutOfBounds or InvalidArgument exception is thrown.
 * 10. Call setVector() function with a vector = [1.0, 2.0, 3.0] and index = 1 and check that
 *    an IndexOutOfBounds or InvalidArgument exception is thrown.
 * 9. Call skipVector() function with index = -1 and check that
 *    an IndexOutOfBounds or InvalidArgument exception is thrown.
 * 10. Call skipVector() function with index = 1 and check that
 *    an IndexOutOfBounds or InvalidArgument exception is thrown.
 */
- (void) testIndexUpdaterIndexOutOfBounds {
    NSError* error;
    CBLCollection* defaultCollection = [self.db defaultCollection: &error];
    
    CBLMutableDocument* mdoc = [self createDocument: @"doc-0"];
    [mdoc setValue: @"a string" forKey: @"value"];
    [defaultCollection saveDocument: mdoc error: &error];
    
    [self createVectorIndexInCollection: defaultCollection
                                   name: @"vector_index"
                                 config: LAZY_VECTOR_INDEX_CONFIG(@"value", 300, 8)];
    
    CBLQueryIndex* index = [defaultCollection indexWithName: @"vector_index" error: &error];
    AssertNotNil(index);
    
    CBLIndexUpdater* updater = [index beginUpdateWithLimit: 10 error: &error];
    AssertEqual(updater.count, 1);
    
    // This is in line with ArrayProtocol, throws RangeException
    [self expectException: @"NSRangeException" in:^{
        [updater valueAtIndex: 1];
    }];
    
    [self expectException: @"NSRangeException" in:^{
        [updater stringAtIndex: 1];
    }];
    
    [self expectException: @"NSRangeException" in:^{
        [updater numberAtIndex: 1];
    }];
    
    [self expectException: @"NSRangeException" in:^{
        [updater integerAtIndex: 1];
    }];
    
    [self expectException: @"NSRangeException" in:^{
        [updater doubleAtIndex: 1];
    }];
    
    [self expectException: @"NSRangeException" in:^{
        [updater floatAtIndex: 1];
    }];
    
    [self expectException: @"NSRangeException" in:^{
        [updater longLongAtIndex: 1];
    }];
    
    [self expectException: @"NSRangeException" in:^{
        [updater dateAtIndex: 1];
    }];
    
    [self expectException: @"NSRangeException" in:^{
        [updater arrayAtIndex: 1];
    }];
    
    [self expectException: @"NSRangeException" in:^{
        [updater dictionaryAtIndex: 1];
    }];
    
    [self expectException: @"NSRangeException" in:^{
        [updater booleanAtIndex: 1];
    }];
    
    [self expectException: @"NSRangeException" in:^{
        [updater setVector: @[@1.0, @2.0, @3.0] atIndex: 1 error: nil];
    }];
    
    [self expectException: @"NSRangeException" in:^{
        [updater skipVectorAtIndex: 1];
    }];
}

/**
 * 26. TestIndexUpdaterCallFinishTwice + 27. TestIndexUpdaterUseAfterFinished
 *
 * Description
 * Test that when calling IndexUpdater's finish() after it was finished,
 * a CuchbaseLiteException is thrown.
 *
 * Steps
 * 1. Copy database words_db.
 * 2. Create a vector index named "words_index" in the _default.words collection.
 *     - expression: "word"
 *     - dimensions: 300
 *     - centroids : 8
 *     - isLazy : true
 * 3. Call beginUpdate() with limit 1 to get an IndexUpdater object.
 *     - Get the word string from the IndexUpdater.
 *     - Query the vector by word from the _default.words collection.
 *     - Convert the vector result which is an array object to a platform's float array.
 *     - Call setVector() with the platform's float array at the index.
 * 4. Call finish() and check that the finish() is successfully called.
 * 5. Call finish() again and check that it throws exception.
 * 6. Count, getValue, setVector, skipVector throw exception.
 */
- (void) testIndexUpdaterUseAfterFinished {
    [self createWordsIndexWithConfig: LAZY_VECTOR_INDEX_CONFIG(@"word", 300, 8)];
    
    NSError* error;
    CBLQueryIndex* index = [self wordsIndex];
    CBLIndexUpdater* updater = [index beginUpdateWithLimit: 1 error: &error];
    AssertNotNil(updater);
    AssertEqual(updater.count, 1);
    
    NSString* word = [updater stringAtIndex: 0];
    NSArray<NSNumber*>* vector = [self vectorForWord: word];
    Assert([updater setVector: vector atIndex: 0 error: &error]);
    Assert([updater finishWithError: &error]);
    
    [self expectException: @"NSInternalInconsistencyException" in:^{
        NSError* outError;
        [updater finishWithError: &outError];
    }];
    
    [self expectException: @"NSInternalInconsistencyException" in:^{
        [updater count];
    }];
        
    [self expectException: @"NSInternalInconsistencyException" in:^{
        [updater valueAtIndex: 0];
    }];
    
    [self expectException: @"NSInternalInconsistencyException" in:^{
        NSError* outError;
        [updater setVector: vector atIndex: 0 error: &outError];
    }];
        
    [self expectException: @"NSInternalInconsistencyException" in:^{
        [updater skipVectorAtIndex: 0];
    }];
}

@end
