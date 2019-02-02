//
//  DateTimeQueryFunctionTest.swift
//  CBL Swift
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
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

import XCTest
import CouchbaseLiteSwift

class DateTimeQueryFunctionTest: CBLTestCase {
    func testStringToMillis() throws {
        try validateStringToMillis("", millis: 0.0)
        try validateStringToMillis("2018-12-32T01:01:01Z", millis: 0.0)
        try validateStringToMillis("1970-01-01T00:00:00Z", millis: 0.0)
        try validateStringToMillis("1970-01-01T00:00:00.123+0000", millis: 123)
        try validateStringToMillis("2018-10-23T11:33:01-0700", millis: 1540319581000)
        try validateStringToMillis("2018-10-23T18:33:01Z", millis: 1540319581000)
        try validateStringToMillis("2018-10-23T18:33:01.123Z", millis: 1540319581123)
        try validateStringToMillis("2020-02-29T23:59:59.000000+0000", millis: 1583020799000)
    }
    
    func testStringToUTC() throws {
        try validateStringToUTC("", utcString: nil)
        try validateStringToUTC("x", utcString: nil)
        
        try validateStringToUTC("2018-10-23T18:33:01Z",
                                utcString: "2018-10-23T18:33:01Z")
        try validateStringToUTC("2018-10-23T11:33:01-0700",
                                utcString: "2018-10-23T18:33:01Z")
        try validateStringToUTC("2018-10-23T11:33:01+03:30",
                                utcString: "2018-10-23T08:03:01Z")
        try validateStringToUTC("2018-10-23T18:33:01.123Z",
                                utcString: "2018-10-23T18:33:01.123Z")
        try validateStringToUTC("2018-10-23T11:33:01.123-0700",
                                utcString: "2018-10-23T18:33:01.123Z")
        try validateStringToUTC("1970-01-01T00:00:00.000000+0000",
                                utcString: "1970-01-01T00:00:00Z")
    }
    
    func testMillisToString() throws {
        let mSec = 1000.0
        var seconds = 0.0
        try validateMillisToString(seconds * mSec, date: Date(timeIntervalSince1970: seconds))
        
        seconds = 0.123
        try validateMillisToString(seconds * mSec, date: Date(timeIntervalSince1970: seconds))
        
        seconds = 1000.123
        try validateMillisToString(seconds * mSec, date: Date(timeIntervalSince1970: seconds))
        
        seconds = 65789245.123;
        try validateMillisToString(seconds * mSec, date: Date(timeIntervalSince1970: seconds))
    }
    
    func testMillisToUTC() throws {
        try validateMillisToUTC(0.0, utcString: "1970-01-01T00:00:00Z")
        try validateMillisToUTC(1540319581000.0, utcString: "2018-10-23T18:33:01Z")
        try validateMillisToUTC(1540319581123.0, utcString: "2018-10-23T18:33:01.123Z")
        try validateMillisToUTC(1540319581999.0, utcString: "2018-10-23T18:33:01.999Z")
    }
    
    // MARK: Helper methods
    
    func validateStringToMillis(_ input: String?, millis: Double) throws {
        let key = "dateString"
        let doc = createDocument().setString(input, forKey: key)
        try saveDocument(doc)
        
        let select = SelectResult.expression(Function.stringToMillis(Expression.property(key)))
        let q = QueryBuilder
            .select([select])
            .from(DataSource.database(db))
        let rs = try q.execute()
        let allResults = rs.allResults()
        XCTAssertEqual(allResults.count, 1)
        
        guard let result = allResults.first else {
            XCTFail()
            return
        }
        XCTAssertEqual(result.double(at: 0) , millis)
        
        try db.purgeDocument(doc)
    }
    
    func validateStringToUTC(_ input: String?, utcString: String?) throws {
        let key = "dateString"
        let doc = createDocument().setString(input, forKey: key)
        try saveDocument(doc)
        
        let select = SelectResult.expression(Function.stringToUTC(Expression.property(key)))
        let q = QueryBuilder
            .select([select])
            .from(DataSource.database(db))
        let rs = try q.execute()
        let allResults = rs.allResults()
        XCTAssertEqual(allResults.count, 1)
        
        guard let result = allResults.first else {
            XCTFail()
            return
        }
        XCTAssertEqual(result.string(at: 0) , utcString)
        
        try db.purgeDocument(doc)
    }
    
    func validateMillisToString(_ input: Double, date: Date) throws {
        let key = "dateString"
        let doc = createDocument().setDouble(input, forKey: key)
        try saveDocument(doc)
        
        let select = SelectResult.expression(Function.millisToString(Expression.property(key)))
        let q = QueryBuilder
            .select([select])
            .from(DataSource.database(db))
        let rs = try q.execute()
        let allResults = rs.allResults()
        XCTAssertEqual(allResults.count, 1)
        
        guard let result = allResults.first else {
            XCTFail()
            return
        }
        
        XCTAssertEqual(result.date(at: 0) , date)
        
        try db.purgeDocument(doc)
    }
    
    func validateMillisToUTC(_ input: Double, utcString: String?) throws {
        let key = "dateString"
        let doc = createDocument().setDouble(input, forKey: key)
        try saveDocument(doc)
        
        let select = SelectResult.expression(Function.millisToUTC(Expression.property(key)))
        let q = QueryBuilder
            .select([select])
            .from(DataSource.database(db))
        let rs = try q.execute()
        let allResults = rs.allResults()
        XCTAssertEqual(allResults.count, 1)
        
        guard let result = allResults.first else {
            XCTFail()
            return
        }
        
        XCTAssertEqual(result.string(at: 0) , utcString)
        
        try db.purgeDocument(doc)
    }
}
