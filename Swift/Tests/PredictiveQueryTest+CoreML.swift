//
//  PredictiveQueryTest+CoreML.swift
//  CouchbaseLite
//
//  Copyright (c) 2018 Couchbase, Inc. All rights reserved.
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

import XCTest
import CoreML
import CouchbaseLiteSwift

@available(macOS 10.13, iOS 11.0, *)
class PredictiveQueryWithCoreMLTest: CBLTestCase {
    
    func coreMLModel(name: String, mustExist: Bool = true) throws -> MLModel? {
        let resource = "mlmodels/\(name)"
        guard let modelURL = urlForResource(name: resource, ofType: "mlmodel") else {
            XCTAssertFalse(mustExist)
            return nil
        }
        
        var mlmodel: MLModel? = nil
        ignoreExpcetion {
            let compiledModelURL = try MLModel.compileModel(at: modelURL)
            mlmodel = try MLModel(contentsOf: compiledModelURL)
        }
        return mlmodel
    }
    
    func model(name: String, mustExist: Bool = true) throws -> CoreMLPredictiveModel? {
        guard let model = try coreMLModel(name: name, mustExist: mustExist) else {
            return nil
        }
        return CoreMLPredictiveModel(mlModel: model)
    }
    
    func createMarsHabitatPricerModelDocuments(_ documents: [[Any?]]) throws {
        for values in documents {
            let doc = createDocument()
            if let v = values[0] {
                doc.setValue(v, forKey: "solarPanels")
            }
            if let v = values[1] {
                doc.setValue(v, forKey: "greenhouses")
            }
            if let v = values[2] {
                doc.setValue(v, forKey: "size")
            }
            if values.count > 3 {
                if let v = values[3] {
                    doc.setValue(v, forKey: "expected_price")
                }
            }
            try saveDocument(doc)
        }
    }
    
    func crateDocumentWithImage(at path: String) throws {
        let res = (path as NSString).deletingPathExtension
        let ext = (path as NSString).pathExtension
        let name = (res as NSString).lastPathComponent
        let doc = createDocument()
        let data = try! dataFromResource(name: res, ofType: ext)
        let type = ext == "jpg" ? "image/jpeg" : "image/png"
        doc.setBlob(Blob.init(contentType: type, data: data), forKey: "image")
        doc.setString(name, forKey: "name")
        try saveDocument(doc)
    }

    func testMarsHabitatPricerModel() throws {
        let model = try self.model(name: "Mars/MarsHabitatPricer")!
        Database.prediction.registerModel(model, withName: "MarsHabitatPricer")
        
        // solarPanels, greenhouses, size, rounded expected_price
        let tests = [[1.0, 1, 750, 1430],
                     [1.5, 2, 1000, 3615],
                     [3.0, 5, 2000, 11635]]
        try createMarsHabitatPricerModelDocuments(tests)
        
        let input = Expression.dictionary(["solarPanels" : Expression.property("solarPanels"),
                                           "greenhouses": Expression.property("greenhouses"),
                                           "size": Expression.property("size")])
        
        let prediction = Function.prediction(model: "MarsHabitatPricer", input: input)
        
        let q = QueryBuilder
            .select(SelectResult.property("expected_price"), SelectResult.expression(prediction))
            .from(DataSource.database(db))
        
        let rows = try verifyQuery(q) { (n, r) in
            let expectedPrice = r.double(at: 0)
            let pred = r.dictionary(at: 1)!
            XCTAssertEqual(pred.double(forKey: "price").rounded(), expectedPrice)
        }
        XCTAssertEqual(rows, UInt64(tests.count));
        
        Database.prediction.unregisterModel(withName: "MarsHabitatPricer")
    }
    
    func testInvalidInput() throws {
        let model = try self.model(name: "Mars/MarsHabitatPricer")!
        Database.prediction.registerModel(model, withName: "MarsHabitatPricer")
        
        let tests = [[1.0, "1", 750],
                     [nil, 2, 1000],
                     [3.0, 5, 2000, 11635]]
        try createMarsHabitatPricerModelDocuments(tests)
        
        let input = Expression.dictionary(["solarPanels" : Expression.property("solarPanels"),
                                           "greenhouses": Expression.property("greenhouses"),
                                           "size": Expression.property("size")])
        let prediction = Function.prediction(model: "MarsHabitatPricer", input: input)
        let q = QueryBuilder
            .select(SelectResult.property("expected_price"), SelectResult.expression(prediction))
            .from(DataSource.database(db))
        let rows = try verifyQuery(q) { (n, r) in
            let pred = r.dictionary(at: 1)
            if let expectedPrice = r.value(at: 0) as? Double {
                XCTAssertEqual(pred!.double(forKey: "price").rounded(), expectedPrice)
            } else {
                XCTAssertNil(pred)
            }
        }
        XCTAssertEqual(rows, UInt64(tests.count));
        
        Database.prediction.unregisterModel(withName: "MarsHabitatPricer")
    }
    
    // Note: Download MobileNet.mlmodel from https://developer.apple.com/documentation/vision/classifying_images_with_vision_and_core_ml
    // and put it at Objective-C/Tests/Support/mlmodels/MobileNet
    func testMobileNetModel() throws {
        guard let model = try self.model(name: "MobileNet/MobileNet", mustExist: false) else {
            return
        }
        Database.prediction.registerModel(model, withName: "MobileNet")
        
        try crateDocumentWithImage(at: "mlmodels/MobileNet/cat.jpg")
        
        let input = Expression.dictionary(["image" : Expression.property("image")])
        let prediction = Function.prediction(model: "MobileNet", input: input)
        let q = QueryBuilder
            .select(SelectResult.expression(prediction))
            .from(DataSource.database(db))
        let rows = try verifyQuery(q) { (n, r) in
            let pred = r.dictionary(at: 0)!
            let label = pred.string(forKey: "classLabel")!.lowercased()
            XCTAssertNotEqual((label as NSString).range(of: "cat").location, NSNotFound)
            let probs = pred.dictionary(forKey: "classLabelProbs")!
            XCTAssertTrue(probs.count > 0)
        }
        XCTAssertEqual(rows, 1);
        
        Database.prediction.unregisterModel(withName: "MobileNet")
    }
    
    // Note: Download OpenFace.mlmodel from https://github.com/iwantooxxoox/Keras-OpenFace
    // and put it at Objective-C/Tests/Support/mlmodels/OpenFace
    func testOpenFaceModel() throws {
        guard let model = try self.model(name: "OpenFace/OpenFace", mustExist: false) else {
            return
        }
        Database.prediction.registerModel(model, withName: "OpenFace")
        
        let faces = ["adams", "lennon-3", "carell", "lennon-2", "lennon-1"]
        for face in faces {
            try crateDocumentWithImage(at: "mlmodels/OpenFace/\(face).png")
        }
        
        // Query the finger print of each face:
        var result: [String: ArrayObject] = [:]
        let input = Expression.dictionary(["data" : Expression.property("image")])
        let prediction = Function.prediction(model: "OpenFace", input: input)
        var q: Query = QueryBuilder
            .select(SelectResult.property("name"), SelectResult.expression(prediction))
            .from(DataSource.database(db))
        var rows = try verifyQuery(q) { (n, r) in
            let name = r.string(at: 0)!
            let pred = r.dictionary(at: 1)!
            let output = pred.array(forKey: "output")!
            XCTAssertEqual(output.count, 128)
            result[name] = output
        }
        XCTAssertEqual(rows, UInt64(faces.count));
        
        // Query the euclidean distance between each face and lennon-1:
        var names: [String] = []
        let lennon1 = result["lennon-1"]
        let vector1 = Expression.parameter("vectorParam")
        let vector2 = prediction.property("output")
        let distance = Function.euclideanDistance(between: vector1, and: vector2)
        q = QueryBuilder
            .select(SelectResult.property("name"), SelectResult.expression(distance))
            .from(DataSource.database(db))
            .orderBy(Ordering.expression(distance))
        let params = Parameters()
        params.setArray(lennon1, forName: "vectorParam")
        q.parameters = params
        rows = try verifyQuery(q) { (n, r) in
            let name = r.string(at: 0)!
            names.append(name)
            XCTAssertNotNil(r.value(at: 1))
            XCTAssertTrue(r.double(at: 1) >= 0)
        }
        XCTAssertEqual(rows, UInt64(faces.count));
        XCTAssertEqual(names, ["lennon-1", "lennon-2", "lennon-3", "carell", "adams"])
        
        Database.prediction.unregisterModel(withName: "OpenFace")
    }
    
}
