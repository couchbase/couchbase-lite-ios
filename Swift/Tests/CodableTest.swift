//
//  Codable.swift
//  CouchbaseLite
//
//  Created by Callum Birks on 27/02/2025.
//  Copyright © 2025 Couchbase. All rights reserved.
//

import XCTest
import CouchbaseLiteSwift

@DocumentModel
class Person: Codable, CustomDebugStringConvertible {
    @DocumentId var id: String?
    let name: String
    let age: UInt
    let hobbies: [Hobby]
    
    init(name: String, age: UInt, hobbies: [Hobby]) {
        self.name = name
        self.age = age
        self.hobbies = hobbies
    }
    
    var debugDescription: String {
        return "[\"age\": \(age), \"name\": \"\(name)\", \"hobbies\":\(hobbies)]"
    }
}

struct Hobby: Codable, Equatable, CustomDebugStringConvertible {
    let name: String
    let frequency: HobbyFrequency
    
    var debugDescription: String {
        return "[\"name\": \"\(name)\", \"frequency\": \"\(frequency)\"]"
    }
}

enum HobbyFrequency: String, Codable, CustomDebugStringConvertible {
    case daily
    case weekly
    
    var debugDescription: String {
        return rawValue
    }
}

class CodableTest: CBLTestCase {
    func testEncodeAndDecode() throws {
        let person = Person(name: "Steve", age: 36, hobbies: [
            Hobby(name: "reading", frequency: .daily),
            Hobby(name: "coding", frequency: .daily),
            Hobby(name: "cycling", frequency: .weekly)
        ])
        
        let collection = try db.defaultCollection()
        try collection.saveDocument(from: person)
        
        let mutableDoc = try collection.document(id: person.id!)!
        debugPrint("MutableDoc:", mutableDoc.toDictionary())
        XCTAssert(mutableDoc.string(forKey: "name") == person.name)
        XCTAssert(mutableDoc.int(forKey: "age") == person.age)
        let docHobbies = mutableDoc.array(forKey: "hobbies")!
        XCTAssert(docHobbies.count == 3)
        XCTAssert(docHobbies[0].dictionary!.string(forKey: "name") == "reading")
        XCTAssert(docHobbies[0].dictionary!.string(forKey: "frequency") == "daily")
        XCTAssert(docHobbies[1].dictionary!.string(forKey: "name") == "coding")
        XCTAssert(docHobbies[1].dictionary!.string(forKey: "frequency") == "daily")
        XCTAssert(docHobbies[2].dictionary!.string(forKey: "name") == "cycling")
        XCTAssert(docHobbies[2].dictionary!.string(forKey: "frequency") == "weekly")

        let personDecoded = try collection.document(id: person.id!, as: Person.self)!
        debugPrint("PersonDecoded:", personDecoded)
        
        XCTAssert(personDecoded.name == person.name)
        XCTAssert(personDecoded.age == person.age)
        XCTAssert(personDecoded.hobbies == person.hobbies)
    }
    
    func testDecodeResult() throws {
        let person = Person(name: "Steve", age: 36, hobbies: [
            Hobby(name: "reading", frequency: .daily),
            Hobby(name: "coding", frequency: .daily),
            Hobby(name: "cycling", frequency: .weekly)
        ])
        
        let collection = try db.defaultCollection()
        try collection.saveDocument(from: person)

        let query = try db.createQuery("SELECT meta().id AS id, name, age, hobbies FROM _")
        let result = try query.execute().next()!
        
        let resultPerson = try result.data(as: Person.self)
        XCTAssert(resultPerson.name == person.name)
        XCTAssert(resultPerson.age == person.age)
        XCTAssert(resultPerson.hobbies == person.hobbies)
    }
    
    func testDecodeResultSet() throws {
        let steve = Person(name: "Steve", age: 36, hobbies: [
            Hobby(name: "reading", frequency: .daily),
            Hobby(name: "coding", frequency: .daily),
            Hobby(name: "cycling", frequency: .weekly)
        ])
        
        let hermione = Person(name: "Hermione", age: 24, hobbies: [
            Hobby(name: "reading", frequency: .daily),
            Hobby(name: "coding", frequency: .daily),
            Hobby(name: "swimming", frequency: .weekly)
        ])
        
        let simon = Person(name: "Simon", age: 40, hobbies: [
            Hobby(name: "reading", frequency: .weekly),
            Hobby(name: "coding", frequency: .daily),
            Hobby(name: "jogging", frequency: .daily)
        ])
        
        let people = [
            steve,
            hermione,
            simon,
        ]
        
        let collection = try db.defaultCollection()
        try collection.saveDocument(from: steve)
        try collection.saveDocument(from: hermione)
        try collection.saveDocument(from: simon)
        
        let query = try db.createQuery("SELECT meta().id AS id, name, age, hobbies FROM _")
        let resultSet = try query.execute()
        
        let resultSetPeople = try resultSet.data(as: Person.self)
        XCTAssert(resultSetPeople.elementsEqual(people, by: { $0.name == $1.name && $0.age == $1.age && $0.hobbies == $1.hobbies }))
    }
}
