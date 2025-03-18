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

@DocumentModel
class Profile: Codable {
    @DocumentId var pid: String?
    var name: ProfileName
    var contacts: [Contact]
    var likes: [String]
    
    init(name: ProfileName, contacts: [Contact], likes: [String]) {
        self.name = name
        self.contacts = contacts
        self.likes = likes
    }
    
    static func == (lhs: Profile, rhs: Document) -> Bool {
        // use DictionaryEquatable protocol to test equality
        return lhs.eq(dict: rhs)
    }
}

struct ProfileName: Codable {
    var first: String
    var last: String
}

struct Contact: Codable {
    var address: ContactAddress
    var emails: [String]
    var phones: [ContactPhone]
    var type: ContactType
}

struct ContactAddress: Codable {
    var city: String
    var state: String
    var street: String
    var zip: String
}

struct ContactPhone: Codable {
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
        let profile = Profile(
            name: .init(first: "Jasper", last: "Grebel"),
            contacts: [
                Contact(
                    address: .init(city: "Burns", state: "KS", street: "19 Florida Loop", zip: "66840"),
                    emails: ["jasper.grebel@nosql-matters.org"],
                    phones: [
                        .init(numbers: ["316-2417120", "316-2767391"], preferred: false, type: .home),
                        .init(numbers: ["316-8833161"], preferred: true, type: .mobile)
                    ],
                    type: .primary
                ),
                Contact(
                    address: .init(city: "Burns", state: "KS", street: "4795 Willow Loop", zip: "66840"),
                    emails: ["Jasper@email.com", "Grebel@email.com"],
                    phones: [
                        .init(numbers: ["316-9487549"], preferred: true, type: .home),
                        .init(numbers: ["316-4737548"], preferred: false, type: .mobile)
                    ],
                    type: .secondary
                )
            ],
            likes: ["shopping"]
        )
        
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
        // Save 'p-0001' from the dataset into the default collection.
        
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
