//
//  WordEmbeddingModel.swift
//  CouchbaseLite
//
//  Copyright (c) 2024 Couchbase, Inc. All rights reserved.
//  COUCHBASE CONFIDENTIAL -- part of Couchbase Lite Enterprise Edition
//

import Foundation
import CouchbaseLiteSwift

public struct WordEmbeddingModel: PredictiveModel {
    
    var db: Database!
    
    public init (db: Database) {
        self.db = db;
    }
    
    public func getWordVector(word: String, collection: String) -> Any? {
        let sql = "select vector from \(collection) where word = '\(word)'"
        let q = try! self.db.createQuery(sql)
        let rs: ResultSet = try! q.execute()
        let results = rs.allResults()
    
        if (results.count == 0) {
            return nil;
        }
            
        let result = results[0];
        return result["vector"]
    }
        
    
    public func predict(input: CouchbaseLiteSwift.DictionaryObject) -> CouchbaseLiteSwift.DictionaryObject? {
        guard let inputWord = input.string(forKey: "word") else {
            fatalError("No word input !!!")
        }
        
        let result = getWordVector(word: inputWord, collection: "words")
        
        if (result == nil) {
            return nil
        }
        
        let output = MutableDictionaryObject()
        output.setValue(result, forKey: "vector")
        return output
    }
}
