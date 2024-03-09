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
    
    public func getWordVector(word: String, collection: String) -> ArrayObject? {
        let sql = "select vector from \(collection) where word = '\(word)'"
        let q = try! self.db.createQuery(sql)
        let rs: ResultSet = try! q.execute()
        let results = rs.allResults()
    
        guard let result = results.first else {
            return nil
        }
        
        return result.array(forKey: "vector")
    }
        
    
    public func predict(input: DictionaryObject) -> DictionaryObject? {
        guard let inputWord = input.string(forKey: "word") else {
            fatalError("No word input !!!")
        }

        guard let result = self.getWordVector(word: inputWord, collection: "words") ??
                           self.getWordVector(word: inputWord, collection: "extwords") else {
            return nil
        }
        
        let output = MutableDictionaryObject()
        output.setValue(result, forKey: "vector")
        return output
    }
}
