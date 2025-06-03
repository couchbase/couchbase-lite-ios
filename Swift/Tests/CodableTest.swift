//
//  Codable.swift
//  CouchbaseLite
//
//  Created by Callum Birks on 27/02/2025.
//  Copyright © 2025 Couchbase. All rights reserved.
//

import CouchbaseLiteSwift
import XCTest

protocol DictionaryEquatable {
    func eq(dict: any DictionaryProtocol) -> Bool
}

class Profile: Codable, Equatable {
    @DocumentID var pid: String?
    var name: ProfileName
    var contacts: [Contact]
    var likes: [String]
    
    init(pid: String? = nil, name: ProfileName, contacts: [Contact], likes: [String]) {
        self.pid = pid
        self.name = name
        self.contacts = contacts
        self.likes = likes
    }
    
    static func == (lhs: Profile, rhs: Profile) -> Bool {
        return lhs.name == rhs.name && lhs.contacts.elementsEqual(rhs.contacts) && lhs.likes.elementsEqual(rhs.likes)
    }

    static func == (lhs: Profile, rhs: DictionaryProtocol) -> Bool {
        // use DictionaryEquatable protocol to test equality
        return lhs.eq(dict: rhs)
    }
    
    static func == (lhs: DictionaryProtocol, rhs: Profile) -> Bool {
        return rhs.eq(dict: lhs)
    }
}

class Person : Profile {
    @DocumentID var id: String?
    var age: Int32
    
    init(id: String? = nil, age: Int32, name: ProfileName, contacts: [Contact], likes: [String]) {
        self.id = id
        self.age = age
        super.init(name: name, contacts: contacts, likes: likes)
    }
    
    init(id: String? = nil, profile: Profile, age: Int32) {
        self.id = id
        self.age = age
        super.init(name: profile.name, contacts: profile.contacts, likes: profile.likes)
    }
    
    required init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.age = try container.decode(Int32.self, forKey: .age)
        let superDecoder = try container.superDecoder()
        try super.init(from: superDecoder)
    }
    
    override func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(age, forKey: .age)
        let superEncoder = container.superEncoder()
        try super.encode(to: superEncoder)
    }
    
    enum CodingKeys : String, CodingKey {
        case age
    }
    
    static func == (lhs: Person, rhs: DictionaryProtocol) -> Bool {
        return lhs.age == rhs["age"].value as? Int32
        && rhs.contains(key: "super")
        && (lhs as Profile) == (rhs["super"].dictionary!)
    }
    
    static func == (lhs: DictionaryProtocol, rhs: Person) -> Bool {
        return rhs.age == lhs["age"].value as? Int32
        && lhs.contains(key: "super")
        && (rhs as Profile) == (lhs["super"].dictionary!)
    }
    
    static func == (lhs: Person, rhs: Person) -> Bool {
        return lhs.age == rhs.age
        && (lhs as Profile) == (rhs as Profile)
    }
}

// Contains nested Profile object
class Car : Codable, Equatable {
    @DocumentID var id: String?
    var name: String
    var driver: Profile
    var topSpeed: Float
    var acceleration: Double
    
    init(id: String? = nil, name: String, driver: Profile, topSpeed: Float, acceleration: Double) {
        self.id = id
        self.name = name
        self.driver = driver
        self.topSpeed = topSpeed
        self.acceleration = acceleration
    }
    
    static func == (lhs: Car, rhs: DictionaryProtocol) -> Bool {
        // use DictionaryEquatable protocol to test equality
        return lhs.eq(dict: rhs)
    }
    
    static func == (lhs: DictionaryProtocol, rhs: Car) -> Bool {
        return rhs.eq(dict: lhs)
    }
    
    static func == (lhs: Car, rhs: Car) -> Bool {
        return lhs.name == rhs.name
        && lhs.driver == rhs.driver
        && lhs.topSpeed == rhs.topSpeed
        && lhs.acceleration == rhs.acceleration
    }
}

// Contains array-nested Profile objects
// Also contains a Dictionary object
class Household : Codable, Equatable {
    @DocumentID var id: String?
    var address: ContactAddress
    var profiles: [Profile]
    var pets: [String : Animal]
    
    init(id: String? = nil, address: ContactAddress, profiles: [Profile], pets: [String : Animal]) {
        self.id = id
        self.address = address
        self.profiles = profiles
        self.pets = pets
    }
    
    static func == (lhs: Household, rhs: DictionaryProtocol) -> Bool {
        // use DictionaryEquatable protocol to test equality
        return lhs.eq(dict: rhs)
    }
    
    static func == (lhs: DictionaryProtocol, rhs: Household) -> Bool {
        return rhs.eq(dict: lhs)
    }
    
    static func == (lhs: Household, rhs: Household) -> Bool {
        return lhs.address == rhs.address
        && lhs.profiles.elementsEqual(rhs.profiles)
        && lhs.pets.allSatisfy { key, value in
            return rhs.pets.keys.contains(key) && rhs.pets[key]! == value
        }
    }
}

// Contains a Blob
class Report : Codable, Equatable {
    @DocumentID var id: String?
    var title: String
    var filed: Bool
    var body: Blob
    
    init(id: String? = nil, title: String, filed: Bool, body: Blob) {
        self.id = id
        self.title = title
        self.filed = filed
        self.body = body
    }
    
    static func == (lhs: Report, rhs: DictionaryProtocol) -> Bool {
        // use DictionaryEquatable protocol to test equality
        return lhs.eq(dict: rhs)
    }
    
    static func == (lhs: DictionaryProtocol, rhs: Report) -> Bool {
        return rhs.eq(dict: lhs)
    }
    
    static func == (lhs: Report, rhs: Report) -> Bool {
        return lhs.title == rhs.title
        && lhs.filed == rhs.filed
        && lhs.body == rhs.body
    }
}

// Contains Blob nested via another struct
class ReportFile : Codable, Equatable {
    @DocumentID var id: String?
    var dateFiled: Date
    var report: Report
    
    init(id: String? = nil, dateFiled: Date, report: Report) {
        self.id = id
        self.dateFiled = dateFiled
        self.report = report
    }
    
    static func == (lhs: ReportFile, rhs: DictionaryProtocol) -> Bool {
        // use DictionaryEquatable protocol to test equality
        return lhs.eq(dict: rhs)
    }
    
    static func == (lhs: DictionaryProtocol, rhs: ReportFile) -> Bool {
        return rhs.eq(dict: lhs)
    }
    
    static func == (lhs: ReportFile, rhs: ReportFile) -> Bool {
        lhs.dateFiled == rhs.dateFiled
        && lhs.report == rhs.report
    }
}

// Contains Blobs nested in array
class Note : Codable, Equatable {
    @DocumentID var id: String?
    var title: String
    var content: String
    var attachments: [Blob]
    
    init(id: String? = nil, title: String, content: String, attachments: [Blob]) {
        self.id = id
        self.title = title
        self.content = content
        self.attachments = attachments
    }
    
    static func == (lhs: Note, rhs: DictionaryProtocol) -> Bool {
        // use DictionaryEquatable protocol to test equality
        return lhs.eq(dict: rhs)
    }
    
    static func == (lhs: DictionaryProtocol, rhs: Note) -> Bool {
        return rhs.eq(dict: lhs)
    }
    
    static func == (lhs: Note, rhs: Note) -> Bool {
        return lhs.title == rhs.title
        && lhs.content == rhs.content
        && lhs.attachments.elementsEqual(rhs.attachments)
    }
}

// Contains nil values and nested nil values
class Favourites : Codable, Equatable {
    @DocumentID var id: String?
    var colour: String?
    var animal: Animal?
    
    static func == (lhs: Favourites, rhs: DictionaryProtocol) -> Bool {
        // use DictionaryEquatable protocol to test equality
        return lhs.eq(dict: rhs)
    }
    
    static func == (lhs: DictionaryProtocol, rhs: Favourites) -> Bool {
        return rhs.eq(dict: lhs)
    }
    
    static func == (lhs: Favourites, rhs: Favourites) -> Bool {
        return lhs.colour == rhs.colour && lhs.animal == rhs.animal
    }
}

class Calculation : Codable, Equatable {
    @DocumentID var id: String?
    var inputA: Int16
    var inputB: Int16
    var op: String
    var output: Int32
    
    init(id: String? = nil, inputA: Int16, inputB: Int16, op: String, output: Int32) {
        self.id = id
        self.inputA = inputA
        self.inputB = inputB
        self.op = op
        self.output = output
    }
    
    static func == (lhs: Calculation, rhs: Calculation) -> Bool {
        return lhs.inputA == rhs.inputA
        && lhs.inputB == rhs.inputB
        && lhs.op == rhs.op
        && lhs.output == rhs.output
    }
}

class LargeCalculation : Codable, Equatable {
    @DocumentID var id: String?
    var inputA: Int64
    var inputB: Int64
    var op: String
    var output: Int64
    
    init(id: String? = nil, inputA: Int64, inputB: Int64, op: String, output: Int64) {
        self.id = id
        self.inputA = inputA
        self.inputB = inputB
        self.op = op
        self.output = output
    }
    
    static func == (lhs: LargeCalculation, rhs: LargeCalculation) -> Bool {
        return lhs.inputA == rhs.inputA
        && lhs.inputB == rhs.inputB
        && lhs.op == rhs.op
        && lhs.output == rhs.output
    }
}

struct Animal : Codable, Equatable {
    var name: String
    // nil if the animal has no legs
    var legs: Int?
}

struct ProfileName: Codable, Equatable {
    var first: String
    var last: String
}

class Contact: Codable, Equatable {
    var address: ContactAddress
    var emails: [String]
    var phones: [ContactPhone]
    var type: ContactType
    
    static func == (lhs: Contact, rhs: Contact) -> Bool {
        return lhs.address == rhs.address
        && lhs.emails.elementsEqual(rhs.emails)
        && lhs.phones.elementsEqual(rhs.phones)
        && lhs.type == rhs.type
    }
}

struct ContactAddress: Codable, Equatable {
    var city: String
    var state: String
    var street: String
    var zip: String
}

struct ContactPhone: Codable, Equatable {
    var numbers: [String]
    var preferred: Bool
    var type: ContactPhoneType
}

enum ContactPhoneType: String, Codable, Equatable {
    case home
    case mobile
}

enum ContactType: String, Codable, Equatable {
    case primary
    case secondary
}

class CodableTest: CBLTestCase {
    // 1. TestCollectionEncode
    func testCollectionEncode() throws {
        // 1. Create a Profile object
        let profile = try decodeFromJSONResource("profiles_100", as: Profile.self, limit: 1).first!
        // 2. Save it to the default collection
        try defaultCollection!.save(from: profile)
        // 3. Assert that profile.pid is not null
        XCTAssertNotNil(profile.pid)
        // 4. Load the Document from the collection
        let document = try defaultCollection!.document(id: profile.pid!)!
        // 5. Assert that all the fields of the document match the fields of the Profile object
        XCTAssert(profile == document)
    }
    
    // 2. TestCollectionDecode
    func testCollectionDecode() throws {
        // 1. Save 'p-0001' from the dataset into the default collection.
        try loadJSONResource("profiles_100", collection: defaultCollection!, limit: 1, idKey: "pid")
        // 2. Load the document into a Profile object
        let profile = try defaultCollection!.document(id: "p-0001", as: Profile.self)
        XCTAssertNotNil(profile)
        // 3. Assert the Profile.id is not null and is 'p-0001'
        XCTAssertNotNil(profile!.pid)
        XCTAssertEqual(profile!.pid, "p-0001")
        // 4. Assert that all of the field values match the source document
        let document = try defaultCollection!.document(id: "p-0001")!
        XCTAssert(profile! == document)
    }
    
    // 3. TestCollectionUpdate
    func testCollectionUpdate() throws {
        // 1. Save 'p-0001' from the dataset into the default collection.
        try loadJSONResource("profiles_100", collection: defaultCollection!, limit: 1, idKey: "pid")
        // 2. Load the document into a Profile object
        let profile = try defaultCollection!.document(id: "p-0001", as: Profile.self)!
        // 3. Assert the Profile.id is not null and is 'p-0001'
        XCTAssertNotNil(profile.pid)
        XCTAssertEqual(profile.pid, "p-0001")
        // 4. Assert that all of the field values match the source document
        var document = try defaultCollection!.document(id: "p-0001")!
        XCTAssert(profile == document)
        // 5. Modify the object
        profile.likes = ["hiking", "cooking"]
        profile.contacts[0].phones[0].numbers.removeLast()
        profile.contacts[1].phones[0].numbers[0] = "+1234567890"
        // 6. Save the modifications
        try defaultCollection!.save(from: profile)
        // 7. Load the Document
        document = try defaultCollection!.document(id: "p-0001")!
        // 8. Assert the field values of the Document match the Profile object
        XCTAssert(document == profile)
        // 9. Modify the object further
        profile.name = .init(first: "Jane", last: "Doe")
        // 10. Save the modifications
        try defaultCollection!.save(from: profile)
        // 11. Load the document
        document = try defaultCollection!.document(id: "p-0001")!
        // 12. Assert the field values match
        XCTAssert(document == profile)
    }
    
    // 4. TestCollectionDelete
    func testCollectionDelete() throws {
        // 1. Create a Profile object
        let profile = try decodeFromJSONResource("profiles_100", as: Profile.self, limit: 1).first!
        // 2. Save it to the default collection
        try defaultCollection!.save(from: profile)
        // 3. Delete it via the object
        try defaultCollection!.delete(for: profile)
        // 4. Assert it is deleted
        XCTAssertNil(try defaultCollection!.document(id: profile.pid!))
        // 5. Modify the Profile object, then save it again
        profile.likes = ["hiking", "reading"]
        try defaultCollection!.save(from: profile)
        // 6. Fetch the Document and assert that all fields match
        let document = try defaultCollection!.document(id: profile.pid!)!
        XCTAssert(profile == document)
    }
    
    // 5. TestCollectionSaveWithConflictHandler
    func testCollectionSaveWithConflictHandler() throws {
        // 1. Create a Profile object
        let profile1 = try decodeFromJSONResource("profiles_100", as: Profile.self, limit: 1).first!
        // 2. Save it to the default collection
        try defaultCollection!.save(from: profile1)
        // 3. Get another reference to the object
        let profile2 = try defaultCollection!.document(id: profile1.pid!, as: Profile.self)!
        // 4. Modify the first reference, and save it
        profile1.likes = ["hiking", "reading"]
        try defaultCollection!.save(from: profile1)
        // 5. Modify the second reference, and save it with conflictHandler
        profile2.name = .init(first: "Updated", last: "Profile")
        let resolved = try defaultCollection!.save(from: profile2) { newProfile, existingProfile in
            // Inside the conflict handler, modify the object and return true
            XCTAssert(existingProfile == profile1)
            XCTAssert(newProfile == profile2)
            newProfile.name = .init(first: "Conflict", last: "Resolved")
            newProfile.likes = ["cooking", "swimming"]
            return true
        }
        XCTAssert(resolved)
        // 6. Assert the fields of object reference 2 match the changes made in the conflict handler
        XCTAssertEqual(profile2.name, .init(first: "Conflict", last: "Resolved"))
        XCTAssertEqual(profile2.likes, ["cooking", "swimming"])
        // 7. Fetch the Document and assert all fields match the changes made in the conflict handler
        let document = try defaultCollection!.document(id: profile1.pid!)!
        XCTAssert(document == profile2)
    }
    
    // 6. TestCollectionSaveWithLastWriteWins
    func testCollectionSaveWithLastWriteWins() throws {
        // 1. Create a Profile object
        let profile1 = try decodeFromJSONResource("profiles_100", as: Profile.self, limit: 1).first!
        // 2. Save it to the default collection
        try defaultCollection!.save(from: profile1)
        // 3. Get another reference to the object
        let profile2 = try defaultCollection!.document(id: profile1.pid!, as: Profile.self)!
        // 4. Modify the first reference, and save it
        profile1.likes = ["hiking", "reading"]
        try defaultCollection!.save(from: profile1)
        // 5. Modify the second reference, and save it with ConcurrencyControl.lastWriteWins
        profile2.name = .init(first: "Updated", last: "Profile")
        let resolved = try defaultCollection!.save(from: profile2, concurrencyControl: .lastWriteWins)
        XCTAssert(resolved)
        // 6. Fetch the Document and assert all fields match the second object reference
        let document = try defaultCollection!.document(id: profile1.pid!)!
        XCTAssert(document == profile2)
    }
    
    // 7. TestCollectionSaveWithFailOnConflict
    func testCollectionSaveWithFailOnConflict() throws {
        // 1. Create a Profile object
        let profile1 = try decodeFromJSONResource("profiles_100", as: Profile.self, limit: 1).first!
        // 2. Save it to the default collection
        try defaultCollection!.save(from: profile1)
        // 3. Get another reference to the object
        let profile2 = try defaultCollection!.document(id: profile1.pid!, as: Profile.self)!
        // 4. Modify the first reference, and save it
        profile1.likes = ["hiking", "reading"]
        try defaultCollection!.save(from: profile1)
        // 5. Modify the second reference, and save it with ConcurrencyControl.lastWriteWins
        profile2.name = .init(first: "Updated", last: "Profile")
        let resolved = try defaultCollection!.save(from: profile2, concurrencyControl: .failOnConflict)
        XCTAssertFalse(resolved)
        // 6. Fetch the Document and assert all fields match the first object reference
        let document = try defaultCollection!.document(id: profile1.pid!)!
        XCTAssert(document == profile1)
    }
    
    // 8. TestQueryResultDecode
    func testQueryResultDecode() throws {
        // 1. Save 'p-0001' from the dataset
        try loadJSONResource("profiles_100", collection: defaultCollection!, limit: 1, idKey: "pid")
        // 2. Create a query to fetch the document
        let query = try db.createQuery("SELECT meta().id AS pid, name, contacts, likes FROM _ LIMIT 1")
        // 3. Execute the query and get the Profile object from the Result
        let result = try query.execute().next()!
        let profile = try result.data(as: Profile.self)
        // 4. Assert that Profile.pid is not null and is 'p-0001'
        XCTAssertEqual(profile.pid, "p-0001")
        // 5. Assert that the field values of the object match the source document
        let document = try defaultCollection!.document(id: "p-0001")!
        XCTAssert(profile == document)
    }
    
    // 9. TestQueryResultDecodeWithDataKey
    func testQueryResultDecodeWithDataKey() throws {
        // 1. Save 'p-0001' from the dataset
        try loadJSONResource("profiles_100", collection: defaultCollection!, limit: 1, idKey: "pid")
        // 2. Create a query to fetch the document
        let query = try db.createQuery("SELECT meta().id AS pid, * FROM _ LIMIT 1")
        // 3. Execute the query and get the Profile object from the Result
        let result = try query.execute().next()!
        let profile = try result.data(as: Profile.self, dataKey: "_")
        // 4. Assert that Profile.pid is not null and is 'p-0001'
        XCTAssertEqual(profile.pid, "p-0001")
        // 5. Assert that the field values of the object match the source document
        let document = try defaultCollection!.document(id: "p-0001")!
        XCTAssert(profile == document)
    }
    
    // 10. TestQueryResultSetDecode
    func testQueryResultSetDecode() throws {
        // 1. Save 'p-0001', 'p-0002', 'p-0003' from the dataset
        try loadJSONResource("profiles_100", collection: defaultCollection!, limit: 3, idKey: "pid")
        // 2. Create a query to fetch the documents
        let query = try db.createQuery("SELECT meta().id AS pid, name, contacts, likes FROM _ ORDER BY meta().id")
        // 3. Execute the query and get the array of Profile objects from the ResultSet
        let resultSet = try query.execute()
        let profiles = try resultSet.data(as: Profile.self)
        // 4. For each element of the resulting array
        for (index, profile) in profiles.enumerated() {
            let docID = "p-\(String(format: "%04d", index + 1))"
            // 1. Assert the Profile.pid matches
            XCTAssertEqual(profile.pid, docID)
            // 2. Assert the field values match the source document
            let document = try defaultCollection!.document(id: docID)!
            XCTAssert(profile == document)
        }
    }
    
    // 11. TestQueryResultSetDecodeWithDataKey
    func testQueryResultSetDecodeWithDataKey() throws {
        // 1. Save 'p-0001', 'p-0002', 'p-0003' from the dataset
        try loadJSONResource("profiles_100", collection: defaultCollection!, limit: 3, idKey: "pid")
        // 2. Create a query to fetch the documents
        let query = try db.createQuery("SELECT meta().id AS pid, * FROM _ ORDER BY meta().id")
        // 3. Execute the query and get the array of Profile objects from the ResultSet
        let resultSet = try query.execute()
        let profiles = try resultSet.data(as: Profile.self, dataKey: "_")
        // 4. For each element of the resulting array
        for (index, profile) in profiles.enumerated() {
            let docID = "p-\(String(format: "%04d", index + 1))"
            // 1. Assert the Profile.pid matches
            XCTAssertEqual(profile.pid, docID)
            // 2. Assert the field values match the source document
            let document = try defaultCollection!.document(id: docID)!
            XCTAssert(profile == document)
        }
    }
    
    // 12. TestQueryResultDecodeMissingID
    func testQueryResultDecodeMissingID() throws {
        // 1. Save 'p-0001' from the dataset
        try loadJSONResource("profiles_100", collection: defaultCollection!, limit: 1, idKey: "pid")
        // 2. Create a query to fetch the document, with ID missing
        let query = try db.createQuery("SELECT * FROM _ LIMIT 1")
        // 3. Execute the query
        let result = try query.execute().next()!
        // 4. Assert that decoding into Profile object fails with an error
        expectError(domain: CBLError.domain, code: CBLError.invalidQuery) {
            let _ = try result.data(as: Profile.self)
        }
    }
    
    // 13. TestQueryResultDecodeMissingField
    func testQueryResultDecodeMissingField() throws {
        // 1. Save 'p-0001' from the dataset
        try loadJSONResource("profiles_100", collection: defaultCollection!, limit: 1, idKey: "pid")
        // 2. Create a query to fetch the document, with field 'name' missing
        let query = try db.createQuery("SELECT meta().id AS pid, contacts, likes FROM _ LIMIT 1")
        // 3. Execute the query
        let result = try query.execute().next()!
        // 4. Assert that decoding into Profile object fails with an error
        expectError(domain: CBLError.domain, code: CBLError.invalidQuery) {
            let _ = try result.data(as: Profile.self)
        }
    }
    
    // 14. TestQueryResultDecodeNonDocumentModel
    func testQueryResultDecodeNonDocumentModel() throws {
        // 1. Save 'p-0001' from the dataset
        try loadJSONResource("profiles_100", collection: defaultCollection!, limit: 1, idKey: "pid")
        // 2. Create a query to fetch a Contact object from the document
        let query = try db.createQuery("SELECT contacts[0] AS contact FROM _ LIMIT 1")
        // 3. Execute the query
        let result = try query.execute().next()!
        // 4. Assert that decoding the Result into Contact succeeds
        let contact = try result.data(as: Contact.self, dataKey: "contact")
        // 5. Assert the fields match the same Contact object from the source document
        let profile = try decodeFromJSONResource("profiles_100", as: Profile.self, limit: 1).first!
        XCTAssert(contact == profile.contacts[0])
    }
    
    // 15. TestCollectionDecodeIncorrectSchema
    func testCollectionDecodeIncorrectSchema() throws {
        // 1. Save a document into the default collection with these fields
        let profileJSON = """
        {
            "name": {
                "first": "Lue",
                "last": "Laserna"
            },
            "contacts": 5,
            "likes": [
                "chatting"
            ]
        }
        """
        let doc = try MutableDocument(json: profileJSON)
        try defaultCollection!.save(document: doc)
        // 2. Assert that `Collection.document(id, as: Profile.self)` throws `decodingError`
        expectError(domain: CBLError.domain, code: CBLError.decodingError) {
            let _ = try self.defaultCollection!.document(id: doc.id, as: Profile.self)
        }
    }
    
    // 16. TestCollectionEncodeNonDocumentModel
    func testCollectionEncodeNonDocumentModel() throws {
        // 1. Create a Contact object
        let profile = try decodeFromJSONResource("profiles_100", as: Profile.self, limit: 1).first!
        let contact = profile.contacts[0]
        // 2. Call Collection.saveDocument(from object)
        // 3. Assert the call to save failed with `InvalidParameter`
        expectError(domain: CBLError.domain, code: CBLError.invalidParameter) {
            try self.defaultCollection!.save(from: contact)
        }
    }
    
    // 17. TestCollectionEncodeGeneratedId
    func testCollectionEncodeGeneratedId() throws {
        // 1. Create a Profile object with pid = nil
        let profile = try decodeFromJSONResource("profiles_100", as: Profile.self, limit: 1).first!
        profile.pid = nil
        // 2. Save it to the default collection
        try defaultCollection!.save(from: profile)
        // 3. Assert that profile.pid is not null
        XCTAssertNotNil(profile.pid)
        // 4. Load the Document from the collection and assert it is not null
        let document = try defaultCollection!.document(id: profile.pid!)
        XCTAssertNotNil(document)
    }
    
    // 18. TestCollectionEncodeNested
    func testCollectionEncodeNested() throws {
        // 1. Create a Car object with ID 'car-001'.
        let profile = try decodeFromJSONResource("profiles_100", as: Profile.self, limit: 1).first!
        let car = Car(id: "car-001", name: "Mini Cooper", driver: profile, topSpeed: 130.0, acceleration: 17.1)
        // 2. Save the object to the default collection
        try defaultCollection!.save(from: car)
        // 3. Load the Document from the collection
        let document = try defaultCollection!.document(id: "car-001")!
        // 4. Assert that all the fields match
        XCTAssert(document == car)
    }
    
    // 19. TestCollectionEncodeArrayNested
    func testCollectionEncodeArrayNested() throws {
        // 1. Create a Household object with ID 'house-001'.
        let profiles = try decodeFromJSONResource("profiles_100", as: Profile.self, limit: 4)
        let house = Household(id: "house-001", address: profiles.first!.contacts[0].address, profiles: profiles, pets: [
            "Mischief" : Animal(name: "Cat", legs: 4),
            "Henry" : Animal(name: "Dog", legs: 4),
            "Serena" : Animal(name: "Fish", legs: nil)
        ])
        // 2. Save the object to the default collection
        try defaultCollection!.save(from: house)
        // 3. Load the Document from the collection
        let document = try defaultCollection!.document(id: "house-001")!
        // 4. Assert that all the fields match
        XCTAssert(document == house)
        let loadedHouse = try defaultCollection!.document(id: "house-001", as: Household.self)!
        XCTAssert(house == loadedHouse)
    }
    
    // 20. TestCollectionEncodeSubclass
    func testCollectionEncodeSubclass() throws {
        // 1. Create a Person object with ID 'person-001'
        let profile = try decodeFromJSONResource("profiles_100", as: Profile.self, limit: 1).first!
        let person = Person(profile: profile, age: 26)
        person.id = "person-001"
        // 2. Save the object to the default collection
        try defaultCollection!.save(from: person)
        // 3. Load the document from the collection
        let document = try defaultCollection!.document(id: "person-001")!
        // 4. Assert that all of the fields match
        XCTAssert(person == document)
        let loadedPerson = try defaultCollection!.document(id: "person-001", as: Person.self)!
        XCTAssert(person == loadedPerson)
    }
    
    // 21. TestCollectionEncodeAndDecodeBlob
    func testCollectionEncodeAndDecodeBlob() throws {
        // 1. Create a Report object with a Blob
        let body = Blob(contentType: "text/plain", data: Data("Hello, World!".utf8))
        let report = Report(title: "My Report", filed: false, body: body)
        // 2. Save the object to the default collection
        try defaultCollection!.save(from: report)
        // 3. Load the Document from the collection
        let document = try defaultCollection!.document(id: report.id!)!
        // 4. Load the Blob from the document
        let docBlob = document.blob(forKey: "body")!
        // 5. Assert the Document Blob contents are identical to the source
        XCTAssertEqual(docBlob, body)
        // 6. Load the object from the collection
        let loadedReport = try defaultCollection!.document(id: report.id!, as: Report.self)!
        // 7. Assert the loaded object Blob is identical to the source
        XCTAssertEqual(loadedReport.body, body)
    }
    
    // 22. TestCollectionEncodeAndDecodeNestedBlob
    func testCollectionEncodeAndDecodeNestedBlob() throws {
        // 1. Create a ReportFile object
        let body = Blob(contentType: "text/plain", data: Data("Hello, World!".utf8))
        let report = Report(title: "My Report", filed: false, body: body)
        let reportFile = ReportFile(dateFiled: Date(), report: report)
        // 2. Save the object to the default collection
        try defaultCollection!.save(from: reportFile)
        // 3. Load the Document from the collection
        let document = try defaultCollection!.document(id: reportFile.id!)!
        // 4. Load the nested Blob from the document
        let docBlob = document["report"]["body"].blob
        // 5. Assert the Document Blob contents are identical to the source
        XCTAssertEqual(docBlob, body)
        // 6. Load the object from the collection
        let loadedReportFile = try defaultCollection!.document(id: reportFile.id!, as: ReportFile.self)!
        // 7. Assert the loaded object nested Blob is identical to the source
        XCTAssertEqual(loadedReportFile.report.body, body)
    }
    
    // CBL-7061
    // Test that Codable can decode Date when it was encoded using Document methods.
    func testCollectionDecodeISO8601Date() throws {
        // Create a ReportFile document
        let body = Blob(contentType: "text/plain", data: Data("Hello, World!".utf8))
        let report = MutableDictionaryObject()
        report.setValue(NSNull(), forKey: "id")
        report.setString("My Report", forKey: "title")
        report.setBoolean(false, forKey: "filed")
        report.setBlob(body, forKey: "body")
        let document = MutableDocument()
        let now = Date()
        document.setDate(now, forKey: "dateFiled")
        document.setDictionary(report, forKey: "report")
        // Save to the default collection
        try defaultCollection!.save(document: document)
        //  Load the object from the collection
        let reportFile = try defaultCollection!.document(id: document.id, as: ReportFile.self)!
        // Assert the loaded object Date is identical to the source (to accuracy of 1 millisecond)
        XCTAssertEqual(reportFile.dateFiled.timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 0.001)
    }
    
    // CBL-7061
    // Test that Codable can decode Date when it was encoded using Swift's default ISO8601 formatter.
    func testCollectionDecodeISO8601DateWithDefaultFormatter() throws {
        // Create a ReportFile document
        let body = Blob(contentType: "text/plain", data: Data("Hello, World!".utf8))
        let report = MutableDictionaryObject()
        report.setValue(NSNull(), forKey: "id")
        report.setString("My Report", forKey: "title")
        report.setBoolean(false, forKey: "filed")
        report.setBlob(body, forKey: "body")
        let document = MutableDocument()
        let now = Date()
        let nowString = ISO8601DateFormatter().string(from: now)
        document.setString(nowString, forKey: "dateFiled")
        document.setDictionary(report, forKey: "report")
        // Save to the default collection
        try defaultCollection!.save(document: document)
        //  Load the object from the collection
        let reportFile = try defaultCollection!.document(id: document.id, as: ReportFile.self)!
        // Assert the loaded object Date is identical to the source (to accuracy of 1 second)
        XCTAssertEqual(reportFile.dateFiled.timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 1)
    }
    
    // 23. TestCollectionEncodeAndDecodeArrayNestedBlob
    func testCollectionEncodeAndDecodeArrayNestedBlob() throws {
        // 1. Create a Note object with array of 3 blobs
        let att1 = Blob(contentType: "application/json", data: Data("{ \"key\": \"value\" }".utf8))
        let att2 = Blob(contentType: "image/jpeg", data: Data())
        let att3 = Blob(contentType: "text/plain", data: Data("Hello, world!".utf8))
        let note = Note(title: "My Note", content: "These are my notes", attachments: [att1, att2, att3])
        // 2. Save the object to the default collection
        try defaultCollection!.save(from: note)
        // 3. Load the Document from the collection
        let document = try defaultCollection!.document(id: note.id!)!
        // 4. Load the array of Blobs from the document
        let attachments = document.array(forKey: "attachments")!.toArray() as! Array<Blob>
        // 5. Assert the blobs are identical to the source blobs
        XCTAssert(attachments.elementsEqual([att1, att2, att3]))
        // 6. Load the object from the collection
        let loadedNote = try defaultCollection!.document(id: note.id!, as: Note.self)!
        // 7. Assert that the loadedNote blobs are identical to the source
        XCTAssert(loadedNote.attachments.elementsEqual([att1, att2, att3]))
    }
    
    func testCollectionDecodeMismatchIntSizes() throws {
        let largeCalc = LargeCalculation(inputA: Int64.max, inputB: Int64.min, op: "add", output: 0)
        try defaultCollection!.save(from: largeCalc)
        expectError(domain: CBLError.domain, code: CBLError.decodingError) {
            let _ = try self.defaultCollection!.document(id: largeCalc.id!, as: Calculation.self)
        }
    }
}

extension Profile : DictionaryEquatable {
    func eq(dict: any DictionaryProtocol) -> Bool {
        guard let nameDict = dict.dictionary(forKey: "name") else {
            return false
        }
        guard let contactsArray = dict.array(forKey: "contacts") else {
            return false
        }
        guard let likesArray = dict.array(forKey: "likes") else {
            return false
        }
        return name.eq(dict: nameDict) && contacts.enumerated().allSatisfy { index, contact in
            guard let contactDict = contactsArray[index].dictionary else { return false }
            return contact.eq(dict: contactDict)
        } && likes.enumerated().allSatisfy { index, like in
            return likesArray[index].string == like
        }
    }
}

extension Car : DictionaryEquatable {
    func eq(dict: any DictionaryProtocol) -> Bool {
        guard let profileDict = dict.dictionary(forKey: "driver") else {
            return false
        }
        return name == dict.string(forKey: "name")
        && driver.eq(dict: profileDict)
        && topSpeed == dict.float(forKey: "topSpeed")
        && acceleration == dict.double(forKey: "acceleration")
    }
}

extension Household : DictionaryEquatable {
    func eq(dict: any DictionaryProtocol) -> Bool {
        guard let addressDict = dict.dictionary(forKey: "address") else {
            return false
        }
        guard let profilesArray = dict.array(forKey: "profiles") else {
            return false
        }
        return address.eq(dict: addressDict)
        && profiles.enumerated().allSatisfy { index, profile in
            guard let profileDict = profilesArray.dictionary(at: index) else {
                return false
            }
            return profile.eq(dict: profileDict)
        }
    }
}

extension Report : DictionaryEquatable {
    func eq(dict: any DictionaryProtocol) -> Bool {
        return title == dict.string(forKey: "title")
        && filed == dict.boolean(forKey: "filed")
        && body == dict.blob(forKey: "body")
    }
}

extension ReportFile : DictionaryEquatable {
    func eq(dict: any DictionaryProtocol) -> Bool {
        guard let reportDict = dict.dictionary(forKey: "report") else {
            return false
        }
        
        return dateFiled == dict.date(forKey: "dateFiled")
        && report.eq(dict: reportDict)
    }
}

extension Note : DictionaryEquatable {
    func eq(dict: any DictionaryProtocol) -> Bool {
        guard let attachmentArray = dict.array(forKey: "attachments") else {
            return false
        }
        
        return title == dict.string(forKey: "title")
        && content == dict.string(forKey: "content")
        && attachments.enumerated().allSatisfy { index, attachment in
            guard let blob = attachmentArray.blob(at: index) else {
                return false
            }
            
            return attachment == blob
        }
    }
}

extension Favourites : DictionaryEquatable {
    func eq(dict: any DictionaryProtocol) -> Bool {
        if !dict.contains(key: "colour") || !dict.contains(key: "animal") {
            return false
        }
        
        if let animalDict = dict.dictionary(forKey: "animal") {
            return colour == dict.string(forKey: "colour")
            && animal?.eq(dict: animalDict) ?? false
        } else {
            return colour == dict.string(forKey: "colour")
            && animal == nil && dict.value(forKey: "animal") is NSNull
        }
    }
}

extension Animal : DictionaryEquatable {
    func eq(dict: any DictionaryProtocol) -> Bool {
        if legs == nil {
            return name == dict.string(forKey: "name")
            && dict.value(forKey: "legs") is NSNull
        } else {
            return name == dict.string(forKey: "name")
            && legs! == dict.int(forKey: "legs")
        }
    }
}

extension ProfileName : DictionaryEquatable {
    func eq(dict: any DictionaryProtocol) -> Bool {
        return dict["first"].string == first && dict["last"].string == last
    }
}

extension Contact : DictionaryEquatable {
    func eq(dict: any DictionaryProtocol) -> Bool {
        guard let addressDict = dict.dictionary(forKey: "address") else {
            return false
        }
        guard let emailsArray = dict.array(forKey: "emails") else {
            return false
        }
        guard let phonesArray = dict.array(forKey: "phones") else {
            return false
        }
        return dict["type"].string == type.rawValue
        && address.eq(dict: addressDict)
        && emails.enumerated().allSatisfy { index, email in
            return emailsArray[index].string == email
        } && phones.enumerated().allSatisfy { index, phone in
            guard let phoneDict = phonesArray[index].dictionary else {
                return false
            }
            return phone.eq(dict: phoneDict)
        }
    }
}

extension ContactAddress : DictionaryEquatable {
    func eq(dict: any DictionaryProtocol) -> Bool {
        return dict["city"].string == city
        && dict["state"].string == state
        && dict["street"].string == street
        && dict["zip"].string == zip
    }
}

extension ContactPhone : DictionaryEquatable {
    func eq(dict: any DictionaryProtocol) -> Bool {
        guard let numbersArray = dict.array(forKey: "numbers") else {
            return false
        }
        return dict["preferred"].boolean == preferred
        && dict["type"].string == type.rawValue
        && numbers.enumerated().allSatisfy { index, number in
            return numbersArray[index].string == number
        }
    }
}
