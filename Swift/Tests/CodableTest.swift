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
    
    init(name: ProfileName, contacts: [Contact], likes: [String]) {
        self.name = name
        self.contacts = contacts
        self.likes = likes
    }
    
    static func == (lhs: Profile, rhs: Profile) -> Bool {
        lhs.name == rhs.name && lhs.contacts.elementsEqual(rhs.contacts) && lhs.likes.elementsEqual(rhs.likes)
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
    var age: Int
    
    init(name: ProfileName, contacts: [Contact], likes: [String], age: Int) {
        self.age = age
        super.init(name: name, contacts: contacts, likes: likes)
    }
    
    init(profile: Profile, age: Int) {
        self.age = age
        super.init(name: profile.name, contacts: profile.contacts, likes: profile.likes)
    }
    
    required init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.age = try container.decode(Int.self, forKey: .age)
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
        return lhs.age == rhs["age"].value as? Int
        && rhs.contains(key: "super")
        && (lhs as Profile) == (rhs["super"].dictionary!)
    }
}

struct ProfileName: Codable, Equatable {
    var first: String
    var last: String
}

struct Contact: Codable, Equatable {
    var address: ContactAddress
    var emails: [String]
    var phones: [ContactPhone]
    var type: ContactType
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

enum ContactPhoneType: String, Codable {
    case home
    case mobile
}

enum ContactType: String, Codable {
    case primary
    case secondary
}

class CodableTest: CBLTestCase {
    func testCollectionEncode() throws {
        // 1. Create a Profile object
        let profile = try decodeFromJSONResource("profiles_100", as: Profile.self, limit: 1).first!
        // 2. Save it to the default collection
        try defaultCollection!.saveDocument(from: profile)
        // 3. Assert that profile.pid is not null
        XCTAssertNotNil(profile.pid)
        // 4. Load the Document from the collection
        let document = try defaultCollection!.document(id: profile.pid!)!
        // 5. Assert that all the fields of the document match the fields of the Profile object
        XCTAssert(profile == document)
    }
    
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
        try defaultCollection!.saveDocument(from: profile)
        // 7. Load the Document
        document = try defaultCollection!.document(id: "p-0001")!
        // 8. Assert the field values of the Document match the Profile object
        XCTAssert(document == profile)
    }
    
    func testCollectionDelete() throws {
        // 1. Create a Profile object
        let profile = try decodeFromJSONResource("profiles_100", as: Profile.self, limit: 1).first!
        // 2. Save it to the default collection
        try defaultCollection!.saveDocument(from: profile)
        // 3. Delete it via the object
        try defaultCollection!.deleteDocument(for: profile)
        // 4. Assert it is deleted
        XCTAssertNil(try defaultCollection!.document(id: profile.pid!))
        // 5. Modify the Profile object, then save it again
        profile.likes = ["hiking", "reading"]
        try defaultCollection!.saveDocument(from: profile)
        // 6. Fetch the Document and assert that all fields match
        let document = try defaultCollection!.document(id: profile.pid!)!
        XCTAssert(profile == document)
    }
    
    func testCollectionSaveWithConflictHandler() throws {
        // 1. Create a Profile object
        let profile1 = try decodeFromJSONResource("profiles_100", as: Profile.self, limit: 1).first!
        // 2. Save it to the default collection
        try defaultCollection!.saveDocument(from: profile1)
        // 3. Get another reference to the object
        let profile2 = try defaultCollection!.document(id: profile1.pid!, as: Profile.self)!
        // 4. Modify the first reference, and save it
        profile1.likes = ["hiking", "reading"]
        try defaultCollection!.saveDocument(from: profile1)
        // 5. Modify the second reference, and save it with conflictHandler
        profile2.name = .init(first: "Updated", last: "Profile")
        let resolved = try defaultCollection!.saveDocument(from: profile2) { newProfile, existingProfile in
            // Inside the conflict handler, modify the object and return true
            XCTAssertEqual(existingProfile, profile1)
            XCTAssertEqual(newProfile, profile2)
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
    
    func testQueryResultDecode() throws {
        // 1. Save 'p-0001' from the dataset
        try loadJSONResource("profiles_100", collection: defaultCollection!, limit: 1, idKey: "pid")
        // 2. Create a query to fetch the document
        let query = try db.createQuery("SELECT meta().id AS pid, * FROM _ LIMIT 1")
        // 3. Execute the query and get the Profile object from the Result
        let result = try query.execute().next()!
        debugPrint(result.keys)
        let profile = try result.data(as: Profile.self)
        // 4. Assert that Profile.pid is not null and is 'p-0001'
        XCTAssertEqual(profile.pid, "p-0001")
        // 5. Assert that the field values of the object match the source document
        let document = try defaultCollection!.document(id: "p-0001")!
        XCTAssert(profile == document)
    }
    
    func testQueryResultSetDecode() throws {
        // 1. Save 'p-0001', 'p-0002', 'p-0003' from the dataset
        try loadJSONResource("profiles_100", collection: defaultCollection!, limit: 3, idKey: "pid")
        // 2. Create a query to fetch the documents
        let query = try db.createQuery("SELECT meta().id AS pid, * FROM _ ORDER BY meta().id")
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
    
    func testCollectionEncodeSubclass() throws {
        // 1. Create a Person object with ID 'person-001'
        let profile = try decodeFromJSONResource("profiles_100", as: Profile.self, limit: 1).first!
        var person = Person(profile: profile, age: 26)
        person.id = "person-001"
        // 2. Save the object to the default collection
        try defaultCollection!.saveDocument(from: person)
        // 3. Load the document from the collection
        let document = try defaultCollection!.document(id: "person-001")!
        debugPrint(document.toDictionary())
        // 4. Assert that all of the fields match
        XCTAssert(person == document)
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
            likesArray[index].string == like
        }
    }
}

extension ProfileName : DictionaryEquatable {
    func eq(dict: any DictionaryProtocol) -> Bool {
        dict["first"].string == first && dict["last"].string == last
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
            emailsArray[index].string == email
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
        dict["city"].string == city
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
            numbersArray[index].string == number
        }
    }
}
