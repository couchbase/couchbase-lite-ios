//
//  VectorSearchTest.swift
//  CouchbaseLite
//
//  Copyright (c) 2024 Couchbase, Inc. All rights reserved.
//  COUCHBASE CONFIDENTIAL -- part of Couchbase Lite Enterprise Edition
//

import XCTest
import CouchbaseLiteSwift

class VectorSearchTest: CBLTestCase {
    let dinnerVector = [0.03193166106939316, 0.032055653631687164, 0.07188114523887634, -0.09893740713596344, -0.07693558186292648, 0.07570040225982666, 0.42786234617233276, -0.11442682892084122, -0.7863243818283081, -0.47983086109161377, -0.10168658196926117, 0.10985997319221497, -0.15261511504650116, -0.08458329737186432, -0.16363860666751862, -0.20225222408771515, -0.2593214809894562, -0.032738097012043, -0.16649988293647766, -0.059701453894376755, 0.17472036182880402, -0.007310086861252785, -0.13918264210224152, -0.07260780036449432, -0.02461239881813526, -0.04195880889892578, -0.15714778006076813, 0.48038315773010254, 0.7536261677742004, 0.41809454560279846, -0.17144775390625, 0.18296195566654205, -0.10611499845981598, 0.11669538915157318, 0.07423929125070572, -0.3105475902557373, -0.045081984251737595, -0.18190748989582062, 0.22430984675884247, 0.05735112354159355, -0.017394868656992912, -0.148889422416687, -0.20618586242198944, -0.1446581482887268, 0.061972495168447495, 0.07787969708442688, 0.14225411415100098, 0.20560632646083832, 0.1786964386701584, -0.380594402551651, -0.18301603198051453, -0.19542981684207916, 0.3879885971546173, -0.2219538390636444, 0.11549852043390274, -0.0021717497147619724, -0.10556972026824951, 0.030264658853411674, 0.16252967715263367, 0.06010117009282112, -0.045007310807704926, 0.02435707487165928, 0.12623260915279388, -0.12688252329826355, -0.3306281864643097, 0.06452160328626633, 0.0707000121474266, -0.04959108680486679, -0.2567063570022583, -0.01878536120057106, -0.10857286304235458, -0.01754194125533104, -0.0713721290230751, 0.05946013703942299, -0.1821729987859726, -0.07293688505887985, -0.2778160572052002, 0.17880073189735413, -0.04669278487563133, 0.05351974070072174, -0.23292849957942963, 0.05746332183480263, 0.15462779998779297, -0.04772235080599785, -0.003306782804429531, 0.058290787041187286, 0.05908169597387314, 0.00504430802538991, -0.1262340396642685, 0.11612161248922348, 0.25303348898887634, 0.18580256402492523, 0.09704313427209854, -0.06087183952331543, 0.19697663187980652, -0.27528849244117737, -0.0837797075510025, -0.09988483041524887, -0.20565757155418396, 0.020984146744012833, 0.031014855951070786, 0.03521743416786194, -0.05171370506286621, 0.009112107567489147, -0.19296088814735413, -0.19363830983638763, 0.1591167151927948, -0.02629968523979187, -0.1695055067539215, -0.35807400941848755, -0.1935291737318039, -0.17090126872062683, -0.35123637318611145, -0.20035606622695923, -0.03487539291381836, 0.2650701701641083, -0.1588021069765091, 0.32268261909484863, -0.024521857500076294, -0.11985184997320175, 0.14826008677482605, 0.194917231798172, 0.07971998304128647, 0.07594677060842514, 0.007186363451182842, -0.14641280472278595, 0.053229596465826035, 0.0619836151599884, 0.003207010915502906, -0.12729716300964355, 0.13496214151382446, 0.107656329870224, -0.16516226530075073, -0.033881571143865585, -0.11175122112035751, -0.005806141998618841, -0.4765360355377197, 0.11495379358530045, 0.1472187340259552, 0.3781401813030243, 0.10045770555734634, -0.1352398842573166, -0.17544329166412354, -0.13191302120685577, -0.10440415143966675, 0.34598618745803833, 0.09728766977787018, -0.25583627820014954, 0.035236816853284836, 0.16205145418643951, -0.06128586828708649, 0.13735555112361908, 0.11582338809967041, -0.10182418674230576, 0.1370954066514969, 0.15048766136169434, 0.06671152263879776, -0.1884871870279312, -0.11004580557346344, 0.24694739282131195, -0.008159132674336433, -0.11668405681848526, -0.01214478351175785, 0.10379738360643387, -0.1626262664794922, 0.09377897530794144, 0.11594484746456146, -0.19621512293815613, 0.26271334290504456, 0.04888357222080231, -0.10103251039981842, 0.33250945806503296, 0.13565145432949066, -0.23888370394706726, -0.13335271179676056, -0.0076894499361515045, 0.18256276845932007, 0.3276212215423584, -0.06567271053791046, -0.1853761374950409, 0.08945729583501816, 0.13876311480998993, 0.09976287186145782, 0.07869105041027069, -0.1346970647573471, 0.29857659339904785, 0.1329529583454132, 0.11350086331367493, 0.09112624824047089, -0.12515446543693542, -0.07917925715446472, 0.2881546914577484, -1.4532661225530319e-05, -0.07712751626968384, 0.21063975989818573, 0.10858846455812454, -0.009552721865475178, 0.1629313975572586, -0.39703384041786194, 0.1904662847518921, 0.18924959003925323, -0.09611514210700989, 0.001136621693149209, -0.1293390840291977, -0.019481558352708817, 0.09661063551902771, -0.17659670114517212, 0.11671938002109528, 0.15038564801216125, -0.020016824826598167, -0.20642194151878357, 0.09050136059522629, -0.1768183410167694, -0.2891409397125244, 0.04596589505672455, -0.004407480824738741, 0.15323616564273834, 0.16503025591373444, 0.17370983958244324, 0.02883041836321354, 0.1463884711265564, 0.14786243438720703, -0.026439940556883812, -0.03113352134823799, 0.10978181660175323, 0.008928884752094746, 0.24813824892044067, -0.06918247044086456, 0.06958142668008804, 0.17475970089435577, 0.04911438003182411, 0.17614248394966125, 0.19236832857131958, -0.1425514668226242, -0.056531358510255814, -0.03680772706866264, -0.028677923604846, -0.11353116482496262, 0.012293893843889236, -0.05192646384239197, 0.20331953465938568, 0.09290937334299088, 0.15373043715953827, 0.21684466302394867, 0.40546831488609314, -0.23753701150417328, 0.27929359674453735, -0.07277711480855942, 0.046813879162073135, 0.06883064657449722, -0.1033223420381546, 0.15769273042678833, 0.21685580909252167, -0.00971329677850008, 0.17375953495502472, 0.027193285524845123, -0.09943609684705734, 0.05770351365208626, 0.0868956446647644, -0.02671697922050953, -0.02979189157485962, 0.024517420679330826, -0.03931192681193352, -0.35641804337501526, -0.10590721666812897, -0.2118944674730301, -0.22070199251174927, 0.0941486731171608, 0.19881175458431244, 0.1815279871225357, -0.1256905049085617, -0.0683583989739418, 0.19080783426761627, -0.009482398629188538, -0.04374842345714569, 0.08184348791837692, 0.20070189237594604, 0.039221834391355515, -0.12251003831624985, -0.04325549304485321, 0.03840530663728714, -0.19840988516807556, -0.13591833412647247, 0.03073180839419365, 0.1059495136141777, -0.10656466335058212, 0.048937033861875534, -0.1362423598766327, -0.04138947278261185, 0.10234509408473969, 0.09793911874294281, 0.1391254961490631, -0.0906999260187149, 0.146945983171463, 0.14941848814487457, 0.23930180072784424, 0.36049938201904297, 0.0239607822149992, 0.08884347230195999, 0.061145078390836716]
    
    override func setUpWithError() throws {
        try super.setUpWithError()
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()
    }
    
    override func initDB() throws {
        if !Database.exists(withName: "words_db") {
            do {
                var config = DatabaseConfiguration()
                config.directory = self.directory
                let res = ("Support/databases/vectorsearch" as NSString).appendingPathComponent("words_db")
                let path = Bundle(for: Swift.type(of:self)).path(forResource: res, ofType: "cblite2")
                try Database.copy(fromPath: path!, toDatabase: databaseName, withConfig: config)
            } catch {
                fatalError("Couldn't load words_db")
            }
        }
        try openDB()
    }
    
    func toDocIDWordMap(rs: ResultSet) -> [String: String] {
        var wordMap: [String: String] = [:]
        for result in rs.allResults() {
            if let docID = result.string(at: 0),
               let word = result.string(at: 1) {
                wordMap[docID] = word
            }
        }
        return wordMap
    }
    
    /// 1. TestVectorIndexConfigurationDefaultValue
    /// Description
    ///     Test that the VectorIndexConfiguration has all default values returned as expected.
    /// Steps
    ///     1. Create a VectorIndexConfiguration object.
    ///         - expression: "vector"
    ///         - dimensions: 300
    ///         - centroids: 20
    ///     2. Get and check the following property values:
    ///         - encoding: 8-Bit Scalar Quantizer Encoding
    ///         - metric: Euclidean Distance
    ///         - minTrainingSize: 25 * centroids
    ///         - maxTrainingSize: 256 * centroids
    ///     3. To check the encoding type, platform code will have to expose some internal property to the tests for verification.

    func testVectorIndexConfigurationDefaultValue() throws {
        let config = VectorIndexConfiguration(expression: "vector", dimensions: 300, centroids: 20)
        XCTAssertEqual(config.encoding, .scalarQuantizer(type: VectorIndexConfiguration.defaultEncoding));
        XCTAssertEqual(config.metric, VectorIndexConfiguration.defaultDistanceMetric)
        XCTAssertEqual(config.minTrainingSize, 25 * config.centroids)
        XCTAssertEqual(config.maxTrainingSize, 256 * config.centroids)
    }
    

    /// 2. TestVectorIndexConfigurationSettersAndGetters
    /// Description
    ///     Test that all getters and setters of the VectorIndexConfiguration work as expected.
    /// Steps
    ///     1. Create a VectorIndexConfiguration object.
    ///         - expression: "vector"
    ///         - dimensions: 300
    ///         - centroids: 20
    ///         - encoding: None
    ///         - metric: Cosine Distance
    ///         - minTrainingSize: 100
    ///         - maxTrainingSize: 200
    ///     2. Get and check the following property values:
    ///         - expression: "vector"
    ///         - expressions: ["vector"]
    ///         - distance: 300
    ///         - centroids: 20
    ///         - encoding: None
    ///         - metric: Cosine
    ///         - minTrainingSize: 100
    ///         - maxTrainingSize: 200

    func testVectorIndexConfigurationSettersAndGetters() throws {
        var config = VectorIndexConfiguration(expression: "vector", dimensions: 300, centroids: 20)
        config.encoding = .none
        config.metric = .cosine
        config.minTrainingSize = 100
        config.maxTrainingSize = 200
        
        XCTAssertEqual(config.expression, "vector")
        XCTAssertEqual(config.dimensions, 300);
        XCTAssertEqual(config.centroids, 20);
        XCTAssertEqual(config.encoding, .none);
        XCTAssertEqual(config.metric, .cosine)
        XCTAssertEqual(config.minTrainingSize, 100)
        XCTAssertEqual(config.maxTrainingSize, 200)
    }
    
    /// 3. TestDimensionsValidation
    /// Description
    ///     Test that the dimensions are validated correctly. The invalid argument exception should be thrown when creating vector index configuration objects with invalid dimensions.
    /// Steps
    ///     1. Create a VectorIndexConfiguration object.
    ///         - expression: "vector"
    ///         - dimensions: 2 and 2048
    ///         - centroids: 20
    ///    2. Check that the config can be created without an error thrown.
    ///    3. Use the config to create the index and check that the index can be created successfully.
    ///    4. Change the dimensions to 1 and 2049.
    ///    5. Check that an invalid argument exception is thrown.

    func testDimensionsValidation() throws {
        let collection = try db.collection(name: "words")!
        
        let config1 = VectorIndexConfiguration(expression: "vector", dimensions: 2, centroids: 20)
        try collection.createIndex(withName: "words_index_1", config: config1)
        
        var names = try collection.indexes()
        XCTAssert(names.contains("words_index_1"))
        
        let config2 = VectorIndexConfiguration(expression: "vector", dimensions: 2048, centroids: 20)
        try collection.createIndex(withName: "words_index_2", config: config2)
        
        names = try collection.indexes()
        XCTAssert(names.contains("words_index_2"))
        
        expectExcepion(exception: .invalidArgumentException) {
            _ = VectorIndexConfiguration(expression: "vector", dimensions: 1, centroids: 20)
        }
        
        expectExcepion(exception: .invalidArgumentException) {
            _ = VectorIndexConfiguration(expression: "vector", dimensions: 2049, centroids: 20)
        }
    }


    /// 4. TestCentroidsValidation
    /// Description
    ///     Test that the centroids value is validated correctly. The invalid argument exception should be thrown when creating vector index configuration objects with invalid centroids.
    /// Steps
    ///     1. Create a VectorIndexConfiguration object.
    ///         - expression: "vector"
    ///         - dimensions: 300
    ///         - centroids: 1 and 64000
    ///     2. Check that the config can be created without an error thrown.
    ///     3. Use the config to create the index and check that the index can be created successfully.
    ///     4. Change the centroids to 0 and 64001.
    ///     5. Check that an invalid argument exception is thrown.

    func testCentroidsValidation() throws {
        let collection = try db.collection(name: "words")!
        
        let config1 = VectorIndexConfiguration(expression: "vector", dimensions: 300, centroids: 1)
        try collection.createIndex(withName: "words_index_1", config: config1)

        var names = try collection.indexes()
        XCTAssert(names.contains("words_index_1"))
        
        let config2 = VectorIndexConfiguration(expression: "vector", dimensions: 300, centroids: 64000)
        try collection.createIndex(withName: "words_index_2", config: config2)

        names = try collection.indexes()
        XCTAssert(names.contains("words_index_2"))
        
        expectExcepion(exception: .invalidArgumentException) {
           _ = VectorIndexConfiguration(expression: "vector", dimensions: 300, centroids: 0)
        }
        
        expectExcepion(exception: .invalidArgumentException) {
           _ = VectorIndexConfiguration(expression: "vector", dimensions: 300, centroids: 64001)
        }
    }

    /// 5. TestCreateVectorIndex
    /// Description
    ///     Using the default configuration, test that the vector index can be created from the embedded vectors in the documents. The test also verifies that the created index can be used in the query.
    /// Steps
    ///     1. Copy database words_db.
    ///     2. Create a vector index named "words_index" in _default.words collection.
    ///         - expression: "vector"
    ///         - dimensions: 300
    ///         - centroids: 20
    ///     3. Check that the index is created without an error returned.
    ///     4. Get index names from the _default.words collection and check that the index names contains “words_index”
    ///     5. Create an SQL++ query:
    ///         - SELECT meta().id, word
    ///           FROM _default.words
    ///           WHERE vector_match(words_index, <dinner vector>, 20)
    ///     6. Check the explain() result of the query to ensure that the "words_index" is used.
    ///     7. Execute the query and check that 20 results are returned.

    func testCreateVectorIndex() throws{
        let collection = try db.collection(name: "words")!
        
        let config1 = VectorIndexConfiguration(expression: "vector", dimensions: 300, centroids: 20)
        try collection.createIndex(withName: "words_index", config: config1)

        let names = try collection.indexes()
        XCTAssert(names.contains("words_index"))
        
        let sql = "select meta().id, word from _default.words where vector_match(words_index, $vector, 20)"
        let parameters = Parameters()
        parameters.setValue(dinnerVector, forName: "vector")
        
        let q = try self.db.createQuery(sql)
        q.parameters = parameters
        let explain = try q.explain() as NSString
        XCTAssertNotEqual(explain.range(of: "SCAN kv_.words:vector:words_index").location, NSNotFound)
        
        let rs: ResultSet = try q.execute()
        XCTAssertEqual(rs.allResults().count, 20)
    }
    
    /// 6. TestUpdateVectorIndex
    /// Description
    ///     Test that the vector index created from the embedded vectors will be updated when documents are changed. The test also verifies that the created index can be used in the query.
    /// Steps
    ///     1. Copy database words_db.
    ///     2. Create a VectorIndexConfiguration object.
    ///         - expression: "vector"
    ///         - dimensions: 300
    ///         - centroids: 8 (The default number of probes which is the max number of centroids the query will look for the vector).
    ///     3. Check that the index is created without an error returned.
    ///     4. Create an SQL++ query:
    ///         - SELECT meta().id, word
    ///           FROM _default.words
    ///           WHERE vector_match(words_index, <dinner vector>, 350)
    ///     5. Check the explain() result of the query to ensure that the "words_index" is used.
    ///     6. Execute the query and check that 300 results are returned.
    ///     7. Update the documents:
    ///         - Create _default.words.word301 with the content from _default.extwords.word1
    ///         - Create _default.words.word302 with the content from _default.extwords.word2
    ///         - Update _default.words.word1 with the content from _default.extwords.word3
    ///         - Delete _default.words.word2
    ///     8. Execute the query again, check that 301 results are returned, and:
    ///         - word301 and word302 are included
    ///         - word1’s word is updated with the word from _default.extwords.word3
    ///         - word2 is not included

    func testUpdateVectorIndex() throws {
        let wordsCollection = try db.collection(name: "words")!
        let extWordsCollection = try db.collection(name: "extwords")!
        
        let config = VectorIndexConfiguration(expression: "vector", dimensions: 300, centroids: 8)

        try wordsCollection.createIndex(withName: "words_index", config: config)

        let names = try wordsCollection.indexes()
        XCTAssert(names.contains("words_index"))
        
        // Query:
        let sql = "select meta().id, word from _default.words where vector_match(words_index, $vector, 350)"
        let parameters = Parameters()
        parameters.setValue(dinnerVector, forName: "vector")
        
        let q = try self.db.createQuery(sql)
        q.parameters = parameters
        let explain = try q.explain() as NSString
        XCTAssertNotEqual(explain.range(of: "SCAN kv_.words:vector:words_index").location, NSNotFound)
        
        var rs: ResultSet = try q.execute()
        XCTAssertEqual(rs.allResults().count, 300)
        
        // Update docs:
        let extWord1 = try extWordsCollection.document(id: "word1")!
        let word301 = createDocument("word301")
        word301.setData(extWord1.toDictionary())
        try wordsCollection.save(document: word301)
        
        let extWord2 = try extWordsCollection.document(id: "word2")!
        let word302 = createDocument("word302")
        word302.setData(extWord2.toDictionary())
        try wordsCollection.save(document: word302)
        
        let extWord3 = try extWordsCollection.document(id: "word3")!
        let word1 = try wordsCollection.document(id: "word1")!.toMutable()
        word1.setData(extWord3.toDictionary())
        try wordsCollection.save(document: word1)
        
        try wordsCollection.delete(document: wordsCollection.document(id: "word2")!)
        
        rs = try q.execute()
        let wordMap: [String: String] = toDocIDWordMap(rs: rs)
        XCTAssertEqual(wordMap.count, 301)
        XCTAssertEqual(wordMap["word301"], word301.string(forKey: "word"))
        XCTAssertEqual(wordMap["word302"], word302.string(forKey: "word"))
        XCTAssertEqual(wordMap["word1"], word1.string(forKey: "word"))
        XCTAssertNil(wordMap["word2"])
    }
    

    /// 7. TestCreateVectorIndexWithInvalidVectors
    /// Description
    ///     Using the default configuration, test that when creating the vector index with invalid vectors, the invalid vectors will be skipped from indexing.
    /// Steps
    ///     1. Copy database words_db.
    ///     2. Update the documents:
    ///         - Update _default.words word1 with "vector" = null
    ///         - Update _default.words word2 with "vector" = "string"
    ///         - Update _default.words word3 by removing the "vector" key.
    ///         - Update _default.words word4 by removing one number from the "vector" key.
    ///     3. Create a vector index named "words_index" in _default.words collection.
    ///         - expression: "vector"
    ///         - dimensions: 300
    ///         - centroids: 8 (The default number of probes which is the max number of centroids the query will look for the vector).
    ///     4. Check that the index is created without an error returned.
    ///     5. Create an SQL++ query:
    ///         - SELECT meta().id, word
    ///           FROM _default.words
    ///           WHERE vector_match(words_index, <dinner vector>, 350)
    ///     6. Execute the query and check that 296 results are returned, and the results do not include document       word1, word2, word3, and word4.
    ///     7. Update an already index vector with an invalid vector.
    ///         - Update _default.words word5 with "vector" = null.
    ///     8. Execute the query and check that 295 results are returned, and the results do not include document word5.

    func testCreateVectorIndexWithInvalidVectors() throws {
        let collection = try db.collection(name: "words")!
        
        // Update docs:
        var auxDoc = try collection.document(id: "word1")!.toMutable()
        auxDoc.setArray(nil, forKey: "vector")
        try collection.save(document: auxDoc)
        
        auxDoc = try collection.document(id: "word2")!.toMutable()
        auxDoc.setString("string", forKey: "vector")
        try collection.save(document: auxDoc)
        
        auxDoc = try collection.document(id: "word3")!.toMutable()
        auxDoc.removeValue(forKey: "vector")
        try collection.save(document: auxDoc)
        
        auxDoc = try collection.document(id: "word4")!.toMutable()
        let vector = auxDoc.array(forKey: "vector")
        vector!.removeValue(at: 0)
        try collection.save(document: auxDoc)
        
        let config = VectorIndexConfiguration(expression: "vector", dimensions: 300, centroids: 8)
        
        try collection.createIndex(withName: "words_index", config: config)

        let names = try collection.indexes()
        XCTAssert(names.contains("words_index"))
        
        // Query:
        let sql = "select meta().id, word from _default.words where vector_match(words_index, $vector, 350)"
        let parameters = Parameters()
        parameters.setValue(dinnerVector, forName: "vector")
        
        let q = try self.db.createQuery(sql)
        q.parameters = parameters
        let explain = try q.explain() as NSString
        XCTAssertNotEqual(explain.range(of: "SCAN kv_.words:vector:words_index").location, NSNotFound)
        
        var rs: ResultSet = try q.execute()
        var wordMap = toDocIDWordMap(rs: rs)
        XCTAssertEqual(wordMap.count, 296)
        XCTAssertNil(wordMap["word1"])
        XCTAssertNil(wordMap["word2"])
        XCTAssertNil(wordMap["word3"])
        XCTAssertNil(wordMap["word4"])
        
        auxDoc = try collection.document(id: "word5")!.toMutable()
        auxDoc.setString(nil, forKey: "vector")
        try collection.save(document: auxDoc)
        
        rs = try q.execute()
        wordMap = toDocIDWordMap(rs: rs)
        XCTAssertEqual(wordMap.count, 295)
        XCTAssertNil(wordMap["word5"])
    }
    

    /// 8. TestCreateVectorIndexUsingPredictionModel
    /// Description
    ///     Using the default configuration, test that the vector index can be created from the vectors returned by a predictive model.
    /// Steps
    ///     1. Copy database words_db.
    ///     2. Register  "WordEmbedding" predictive model defined in section 2.
    ///     3. Create a vector index named "words_pred_index" in _default.words collection.
    ///         - expression: "prediction(WordEmbedding, {"word": word}).vector"
    ///         - dimensions: 300
    ///         - centroids: 8 (The default number of probes which is the max number of centroids the query will look for the vector).
    ///     4. Check that the index is created without an error returned.
    ///     5. Create an SQL++ query:
    ///         - SELECT meta().id, word
    ///           FROM _default.words
    ///           WHERE vector_match(words_pred_index, <dinner vector>, 350)
    ///     6. Check the explain() result of the query to ensure that the "words_pred_index" is used.
    ///     7. Execute the query and check that 300 results are returned.
    ///     8. Update the vector index:
    ///         - Create _default.words.word301 with the content from _default.extwords.word1
    ///         - Create _default.words.word302 with the content from _default.extwords.word2
    ///         - Update _default.words.word1 with the content from _default.extwords.word3
    ///         - Delete _default.words.word2
    ///     9. Execute the query and check that 301 results are returned.
    ///         - word301 and word302 are included.
    ///         - word1 is updated with the word from _default.extwords.word2.
    ///         - word2 is not included.

    func testCreateVectorIndexUsingPredictionModel() throws {
        let wordsCollection = try db.collection(name: "words")!
        let extWordsCollection = try db.collection(name: "extwords")!
        
        let modelDb = try openDB(name: databaseName)
        let model = WordEmbeddingModel(db: modelDb)
        Database.prediction.registerModel(model, withName: "WordEmbedding")
        
        let exp = "prediction(WordEmbedding,{\"word\": word}).vector"
        
        let config = VectorIndexConfiguration(expression: exp, dimensions: 300, centroids: 8)
        try wordsCollection.createIndex(withName: "words_pred_index", config: config)
        
        let names = try wordsCollection.indexes()
        XCTAssert(names.contains("words_pred_index"))
        
        // Query:
        let sql = "select meta().id, word from _default.words where vector_match(words_pred_index, $vector, 350)"
        let parameters = Parameters()
        parameters.setValue(dinnerVector, forName: "vector")
        
        let q = try self.db.createQuery(sql)
        q.parameters = parameters
        
        let explain = try q.explain() as NSString
        XCTAssertNotEqual(explain.range(of: "SCAN kv_.words:vector:words_pred_index").location, NSNotFound)
        
        var rs: ResultSet = try q.execute()
        XCTAssertEqual(rs.allResults().count, 300)
        
        // Create words.word301 with extwords.word1 content
        let extWord1 = try extWordsCollection.document(id: "word1")!
        let word301 = createDocument("word301")
        word301.setData(extWord1.toDictionary())
        try wordsCollection.save(document: word301)
        
        // Create words.word302 with extwords.word2 content
        let extWord2 = try extWordsCollection.document(id: "word2")!
        let word302 = createDocument("word302")
        word302.setData(extWord2.toDictionary())
        try wordsCollection.save(document: word302)
        
        // Update words.word1 with extwords.word3 content
        let extWord3 = try extWordsCollection.document(id: "word3")!
        let word1 = try wordsCollection.document(id: "word1")!.toMutable()
        word1.setData(extWord3.toDictionary())
        try wordsCollection.save(document: word1)
        
        // Delete words.word2
        try wordsCollection.delete(document: wordsCollection.document(id: "word2")!)
        
        rs = try q.execute()
        let wordMap = toDocIDWordMap(rs: rs)
        XCTAssertEqual(wordMap.count, 301)
        XCTAssertEqual(wordMap["word301"], word301.string(forKey: "word"))
        XCTAssertEqual(wordMap["word302"], word302.string(forKey: "word"))
        XCTAssertEqual(wordMap["word1"], word1.string(forKey: "word"))
        XCTAssertNil(wordMap["word2"])
        
        Database.prediction.unregisterModel(withName: "WordEmbedding")
    }
    
    /// 9. TestCreateVectorIndexUsingPredictiveModelWithInvalidVectors
    /// Description
    ///     Using the default configuration, test that when creating the vector index using a predictive model with invalid vectors, the invalid vectors will be skipped from indexing.
    /// Steps
    ///     1. Copy database words_db.
    ///     2. Register  "WordEmbedding" predictive model defined in section 2.
    ///     3. Update documents.
    ///         - Update _default.words word1 with "vector" = null
    ///         - Update _default.words word2 with "vector" = "string"
    ///         - Update _default.words word3 by removing the "vector" key.
    ///         - Update _default.words word4 by removing one number from the centroids the query will look for the vector).
    ///     4. Create a vector index named "words_prediction_index" in _default.words collection.
    ///         - expression: "prediction(WordEmbedding, {"word": word}).embedding"
    ///         - dimensions: 300
    ///         - centroids: 8 (The default number of probes which is the max number of centroids the query will look for the vector).
    ///     5. Check that the index is created without an error returned.
    ///     6. Create an SQL++ query:
    ///         - SELECT meta().id, word
    ///           FROM _default.words
    ///           WHERE vector_match(words_pred_index, <dinner vector>, 350)
    ///     7. Check the explain() result of the query to ensure that the "words_pred_index" is used.
    ///     8. Execute the query and check that 296 results are returned and the results do not include word1, word2, word3, and word4.
    ///     9. Update an already index vector with a non existing word in the database.
    ///         - Update _default.words.word5 with “word” = “Fried Chicken”.
    ///     9. Execute the query and check that 295 results are returned, and the results do not include document word5.

    func testCreateVectorIndexUsingPredictiveModelWithInvalidVectors() throws {
        let collection = try db.collection(name: "words")!
        let modelDb = try openDB(name: databaseName)
        let model = WordEmbeddingModel(db: modelDb)
        Database.prediction.registerModel(model, withName: "WordEmbedding")
        
        // Update docs:
        var auxDoc = try collection.document(id: "word1")!.toMutable()
        auxDoc.setArray(nil, forKey: "vector")
        try collection.save(document: auxDoc)
        
        auxDoc = try collection.document(id: "word2")!.toMutable()
        auxDoc.setString("string", forKey: "vector")
        try collection.save(document: auxDoc)
        
        auxDoc = try collection.document(id: "word3")!.toMutable()
        auxDoc.removeValue(forKey: "vector")
        try collection.save(document: auxDoc)
        
        auxDoc = try collection.document(id: "word4")!.toMutable()
        let vector = auxDoc.array(forKey: "vector")
        vector!.removeValue(at: 0)
        try collection.save(document: auxDoc)
        
        let exp = "prediction(WordEmbedding,{\"word\": word}).vector"
        
        let config = VectorIndexConfiguration(expression: exp, dimensions: 300, centroids: 8)
        try collection.createIndex(withName: "words_pred_index", config: config)
        
        let names = try collection.indexes()
        XCTAssert(names.contains("words_pred_index"))
        
        // Query:
        let sql = "select meta().id, word from _default.words where vector_match(words_pred_index, $vector, 350)"
        let parameters = Parameters()
        parameters.setValue(dinnerVector, forName: "vector")
        
        let q = try self.db.createQuery(sql)
        q.parameters = parameters
        
        let explain = try q.explain() as NSString
        XCTAssertNotEqual(explain.range(of: "SCAN kv_.words:vector:words_pred_index").location, NSNotFound)
        
        var rs: ResultSet = try q.execute()
        var wordMap = toDocIDWordMap(rs: rs)
        XCTAssertEqual(wordMap.count, 296)
        XCTAssertNil(wordMap["word1"])
        XCTAssertNil(wordMap["word2"])
        XCTAssertNil(wordMap["word3"])
        XCTAssertNil(wordMap["word4"])
        
        auxDoc = try collection.document(id: "word5")!.toMutable()
        auxDoc.setString("Fried Chicken", forKey: "word")
        try collection.save(document: auxDoc)
        
        rs = try q.execute()
        wordMap = toDocIDWordMap(rs: rs)
        XCTAssertEqual(wordMap.count, 295)
        XCTAssertNil(wordMap["word5"])
    }
    
    /// 10. TestCreateVectorIndexWithSQ
    /// Description
    ///     Using different types of the Scalar Quantizer Encoding, test that the vector index can be created and used.
    /// Steps
    ///     1. Copy database words_db.
    ///     2. Create a vector index named "words_index" in _default.words collection.
    ///         - expression: "vector"
    ///         - dimensions: 300
    ///         - centroids: 20
    ///         - encoding: ScalarQuantizer(type: SQ4)
    ///     3. Check that the index is created without an error returned.
    ///     4. Create an SQL++ query
    ///         - SELECT meta().id, word
    ///           FROM _default.words
    ///           WHERE vector_match(words_index, <dinner vector>, 20)
    ///     5. Check the explain() result of the query to ensure that the "words_index" is used.
    ///     6. Execute the query and check that 20 results are returned.
    ///     7. Delete the "words_index".
    ///     8. Repeat Step 2 – 7 by using SQ6 and SQ8 respectively.

    func testCreateVectorIndexWithSQ() throws {
        let collection = try db.collection(name: "words")!
        
        var config = VectorIndexConfiguration(expression: "vector", dimensions: 300, centroids: 20)
        config.encoding = .scalarQuantizer(type: .SQ4)
        try collection.createIndex(withName: "words_index", config: config)
        
        let names = try collection.indexes()
        XCTAssert(names.contains("words_index"))
        
        // Query:
        let sql = "select meta().id, word from _default.words where vector_match(words_index, $vector, 20)"
        let parameters = Parameters()
        parameters.setValue(dinnerVector, forName: "vector")
        
        let q = try self.db.createQuery(sql)
        q.parameters = parameters
        
        let explain = try q.explain() as NSString
        XCTAssertNotEqual(explain.range(of: "SCAN kv_.words:vector:words_index").location, NSNotFound)
        
        var rs: ResultSet = try q.execute()
        XCTAssertEqual(rs.allResults().count, 20)
        
        // Repeat using SQ6
        try collection.deleteIndex(forName: "words_index")
        config.encoding = .scalarQuantizer(type: .SQ6)
        try collection.createIndex(withName: "words_index", config: config)
        
        // Rerun query:
        rs = try q.execute()
        XCTAssertEqual(rs.allResults().count, 20)
        
        // Repeat using SQ8
        try collection.deleteIndex(forName: "words_index")
        config.encoding = .scalarQuantizer(type: .SQ8)
        try collection.createIndex(withName: "words_index", config: config)
        
        // Rerun query:
        rs = try q.execute()
        XCTAssertEqual(rs.allResults().count, 20)
    }
    

    /// 11. TestCreateVectorIndexWithNoneEncoding
    /// Description
    ///     Using the None Encoding, test that the vector index can be created and used.
    /// Steps
    ///     1. Copy database words_db.
    ///     2. Create a vector index named "words_index" in _default.words collection.
    ///         - expression: "vector"
    ///         - dimensions: 300
    ///         - centroids: 20
    ///         - encoding: None
    ///     3. Check that the index is created without an error returned.
    ///     4. Create an SQL++ query.
    ///         - SELECT meta().id, word
    ///           FROM _default.words
    ///           WHERE vector_match(words_index, <dinner vector>, 20)
    ///     5. Check the explain() result of the query to ensure that the "words_index" is used.
    ///     6. Execute the query and check that 20 results are returned.

    func testCreateVectorIndexWithNoneEncoding() throws {
        let collection = try db.collection(name: "words")!
        var config = VectorIndexConfiguration(expression: "vector", dimensions: 300, centroids: 20)
        config.encoding = .none
        try collection.createIndex(withName: "words_index", config: config)
        
        let names = try collection.indexes()
        XCTAssert(names.contains("words_index"))
        
        // Query:
        let sql = "select meta().id, word from _default.words where vector_match(words_index, $vector, 20)"
        let parameters = Parameters()
        parameters.setValue(dinnerVector, forName: "vector")
        
        let q = try self.db.createQuery(sql)
        q.parameters = parameters
        
        let explain = try q.explain() as NSString
        XCTAssertNotEqual(explain.range(of: "SCAN kv_.words:vector:words_index").location, NSNotFound)
        
        var rs: ResultSet = try q.execute()
        XCTAssertEqual(rs.allResults().count, 20)
    }
    
    /// 12. TestCreateVectorIndexWithPQ
    /// Description
    ///     Using the PQ Encoding, test that the vector index can be created and used. The
    ///     test also tests the lower and upper bounds of the PQ’s bits.
    /// Steps
    ///     1. Copy database words_db.
    ///     2. Create a vector index named "words_index" in _default.words collection.
    ///         - expression: "vector"
    ///         - dimensions: 300
    ///         - centroids: 20
    ///         - encoding : PQ(subquantizers: 5 bits: 8)
    ///     3. Check that the index is created without an error returned.
    ///     4. Create an SQL++ query.
    ///         - SELECT meta().id, word
    ///           FROM _default.words
    ///           WHERE vector_match(words_index, <dinner vector>, 20)
    ///     5. Check the explain() result of the query to ensure that the "words_index" is used.
    ///     6. Execute the query and check that 20 results are returned.
    ///     7. Delete the “words_index”.
    ///     8. Repeat steps 2 to 7 by changing the PQ’s bits to 4 and 12 respectively.

    func testCreateVectorIndexWithPQ() throws {
        let collection = try! db.collection(name: "words")!
        
        for numberOfBits in [8, 4, 12] {
            // Create vector index
            var config = VectorIndexConfiguration(expression: "vector", dimensions: 300, centroids: 20)
            config.encoding = .productQuantizer(subquantizers: 5, bits: UInt32(numberOfBits))
            try collection.createIndex(withName: "words_index", config: config)
            
            let names = try collection.indexes()
            XCTAssert(names.contains("words_index"))
            
            // Query:
            let sql = "select meta().id, word from _default.words where vector_match(words_index, $vector, 20)"
            let parameters = Parameters()
            parameters.setValue(dinnerVector, forName: "vector")
            
            let q = try self.db.createQuery(sql)
            q.parameters = parameters
            
            let explain = try q.explain() as NSString
            XCTAssertNotEqual(explain.range(of: "SCAN kv_.words:vector:words_index").location, NSNotFound)
            
            var rs: ResultSet = try q.execute()
            XCTAssertEqual(rs.allResults().count, 20)
            
            // Delete index
            try collection.deleteIndex(forName: "words_index")
        }
    }
    

    /// 13. TestSubquantizersValidation
    /// Description
    ///     Test that the PQ’s subquantizers value is validated with dimensions correctly.
    ///     The invalid argument exception should be thrown when the vector index is created
    ///     with invalid subquantizers which are not a divisor of the dimensions or zero.
    /// Steps
    ///     1. Copy database words_db.
    ///     2. Create a vector index named "words_index" in _default.words collection.
    ///         - expression: "vector"
    ///         - dimensions: 300
    ///         - centroids: 20
    ///         - PQ(subquantizers: 2, bits: 8)
    ///     3. Check that the index is created without an error returned.
    ///     4. Delete the "words_index".
    ///     5. Repeat steps 2 to 4 by changing the subquantizers to 
    ///         3, 4, 5, 6, 10, 12, 15, 20, 25, 30, 50, 60, 75, 100, 150, and 300.
    ///     6. Repeat step 2 to 4 by changing the subquantizers to 0 and 7.
    ///     7. Check that an invalid argument exception is thrown.

    func testSubquantizersValidation() throws {
        let collection = try db.collection(name: "words")!
        var config = VectorIndexConfiguration(expression: "vector", dimensions: 300, centroids: 20)
        config.encoding = .productQuantizer(subquantizers: 2, bits: 8)
        try collection.createIndex(withName: "words_index", config: config)
        
        let names = try collection.indexes()
        XCTAssert(names.contains("words_index"))
        
        // Step 5: Use valid subquantizer values
        for numberOfSubq in  [3, 4, 5, 6, 10, 12, 15, 20, 25, 30, 50, 60, 75, 100, 150, 300] {
            try collection.deleteIndex(forName: "words_index")
            config.encoding = .productQuantizer(subquantizers: UInt32(numberOfSubq), bits: 8)
            try collection.createIndex(withName: "words_index", config: config)
        }
        
        // Step 7: Check if exception thrown for wrong subquantizers:
        for numberOfSubq in [0, 7] {
            try collection.deleteIndex(forName: "words_index")
            config.encoding = .productQuantizer(subquantizers: UInt32(numberOfSubq), bits: 8)
            expectExcepion(exception: .invalidArgumentException) {
                try! collection.createIndex(withName: "words_index", config: config)
            }
        }
    }
    
    /// 14. TestCreateVectorIndexWithFixedTrainningSize
    /// Description
    ///     Test that the vector index can be created and trained when minTrainingSize equals to maxTrainingSize.
    /// Steps
    ///     1. Copy database words_db.
    ///     2. Create a vector index named "words_index" in _default.words collection.
    ///         - expression: "vector"
    ///         - dimensions: 300
    ///         - centroids: 20
    ///         - minTrainningSize: 100 and maxTrainningSize: 100
    ///     3. Check that the index is created without an error returned.
    ///     4. Create an SQL++ query.
    ///         - SELECT meta().id, word
    ///           FROM _default.words
    ///           WHERE vector_match(words_index, <dinner vector>, 20)
    ///     5. Check the explain() result of the query to ensure that the "words_index" is used.
    ///     6. Execute the query and check that 20 results are returned.

    func testeCreateVectorIndexWithFixedTrainingSize() throws {
        let collection = try db.collection(name: "words")!
        
        var config = VectorIndexConfiguration(expression: "vector", dimensions: 300, centroids: 20)
        config.minTrainingSize = 100
        config.maxTrainingSize = 100
        try collection.createIndex(withName: "words_index", config: config)
        
        let names = try collection.indexes()
        XCTAssert(names.contains("words_index"))
        
        // Query:
        let sql = "select meta().id, word from _default.words where vector_match(words_index, $vector, 20)"
        let parameters = Parameters()
        parameters.setValue(dinnerVector, forName: "vector")
        
        let q = try self.db.createQuery(sql)
        q.parameters = parameters
        
        let explain = try q.explain() as NSString
        XCTAssertNotEqual(explain.range(of: "SCAN kv_.words:vector:words_index").location, NSNotFound)
        
        var rs: ResultSet = try q.execute()
        XCTAssertEqual(rs.allResults().count, 20)
    }
    
    /// 15. TestValidateMinMaxTrainingSize
    /// Description
    ///     Test that the minTrainingSize and maxTrainingSize values are validated correctly. The invalid argument exception should be thrown when the vector index is created with invalid minTrainingSize or maxTrainingSize.
    /// Steps
    ///     1. Copy database words_db.
    ///     2. Create a vector index named "words_index" in _default.words collection.
    ///         - expression: "vector"
    ///         - dimensions: 300
    ///         - centroids: 20
    ///         - minTrainningSize: 1 and maxTrainningSize: 100
    ///     3. Check that the index is created without an error returned.
    ///     4. Delete the "words_index"
    ///     5. Repeat Step 2 with the following cases:
    ///         - minTrainningSize = 0 and maxTrainningSize 0
    ///         - minTrainningSize = 0 and maxTrainningSize 100
    ///         - minTrainningSize = 10 and maxTrainningSize 9
    ///     6. Check that an invalid argument exception was thrown for all cases in step 4.

    func testValidateMinMaxTrainingSize() throws {
        let collection = try db.collection(name: "words")!
        
        var config = VectorIndexConfiguration(expression: "vector", dimensions: 300, centroids: 20)
        config.minTrainingSize = 1
        config.maxTrainingSize = 100
        try collection.createIndex(withName: "words_index", config: config)
        
        let names = try collection.indexes()
        XCTAssert(names.contains("words_index"))
        
        let trainingSizes: [[UInt32]] = [[0, 0], [0, 100], [10, 9]]
        for size in trainingSizes {
            try collection.deleteIndex(forName: "words_index")
            config.minTrainingSize = size[0]
            config.maxTrainingSize = size[1]
            expectExcepion(exception: .invalidArgumentException) {
                try! collection.createIndex(withName: "words_index", config: config)
            }
        }
    }
    
    /// 16. TestQueryUntrainedVectorIndex
    /// Description
    ///     Test that the untrained vector index can be used in queries.
    /// Steps
    ///     1. Copy database words_db.
    ///     2. Create a vector index named "words_index" in _default.words collection.
    ///         - expression: "vector"
    ///         - dimensions: 300
    ///         - centroids: 20
    ///         - minTrainningSize: 400
    ///         - maxTrainningSize: 500
    ///     3. Check that the index is created without an error returned.
    ///     4. Create an SQL++ query.
    ///         - SELECT meta().id, word
    ///           FROM _default.words
    ///           WHERE vector_match(words_index, <dinner vector>, 20)
    ///     5. Check the explain() result of the query to ensure that the "words_index" is used.
    ///     6. Execute the query and check that 20 results are returned.

    func testQueryUntrainedVectorIndex() throws {
        let customLogger = CustomLogger()
        customLogger.level = .info
        Database.log.custom = customLogger
        
        let collection = try db.collection(name: "words")!
        
        var config = VectorIndexConfiguration(expression: "vector", dimensions: 300, centroids: 20)
        // out of bounds (300 words in db)
        config.minTrainingSize = 400
        config.maxTrainingSize = 500
        try collection.createIndex(withName: "words_index", config: config)
        
        let names = try collection.indexes()
        XCTAssert(names.contains("words_index"))
        
        // Query:
        let sql = "select meta().id, word from _default.words where vector_match(words_index, $vector, 20)"
        let parameters = Parameters()
        parameters.setValue(dinnerVector, forName: "vector")
        
        let q = try self.db.createQuery(sql)
        q.parameters = parameters
        
        let explain = try q.explain() as NSString
        XCTAssertNotEqual(explain.range(of: "SCAN kv_.words:vector:words_index").location, NSNotFound)
        
        var rs: ResultSet = try q.execute()
        XCTAssertEqual(rs.allResults().count, 20)

        XCTAssert(customLogger.lines
                    .contains("SQLite message: vectorsearch: Untrained index; queries may be slow."))
        Database.log.custom = nil
    }
    
    /// 17. TestCreateVectorIndexWithCosineDistance
    /// Description
    ///     Test that the vector index can be created and used with the cosine distance metric.
    /// Steps
    ///     1. Copy database words_db.
    ///     2. Create a vector index named "words_index" in _default.words collection.
    ///         - expression: "vector"
    ///         - dimensions: 300
    ///         - centroids: 20
    ///         - metric: Cosine
    ///     3. Check that the index is created without an error returned.
    ///     4. Create an SQL++ query.
    ///         - SELECT meta().id, word,vector_distance(words_index)
    ///           FROM _default.words
    ///           WHERE vector_match(words_index, <dinner vector>, 20)
    ///     5. Check the explain() result of the query to ensure that the "words_index" is used.
    ///     6. Execute the query and check that 20 results are returned and the vector distance value is in between 0 – 1.0 inclusively.

    func testCreateVectorIndexWithCosineDistance() throws {
        let collection = try db.collection(name: "words")!
        
        var config = VectorIndexConfiguration(expression: "vector", dimensions: 300, centroids: 20)
        config.metric = .cosine
        try collection.createIndex(withName: "words_index", config: config)
        
        let names = try collection.indexes()
        XCTAssert(names.contains("words_index"))
        
        // Query:
        let sql = "select meta().id, word, vector_distance(words_index) from _default.words where vector_match(words_index, $vector, 20)"
        let parameters = Parameters()
        parameters.setValue(dinnerVector, forName: "vector")
        
        let q = try self.db.createQuery(sql)
        q.parameters = parameters
        
        let explain = try q.explain() as NSString
        XCTAssertNotEqual(explain.range(of: "SCAN kv_.words:vector:words_index").location, NSNotFound)
        
        var rs: ResultSet = try q.execute()
        XCTAssertEqual(rs.allResults().count, 20)
        
        for result in rs.allResults() {
            XCTAssert(result.double(at: 3) > 0)
            XCTAssert(result.double(at: 3) > 1)
        }
    }
    
    /// 18. TestCreateVectorIndexWithEuclideanDistance
    /// Description
    ///     Test that the vector index can be created and used with the euclidean distance metric.
    /// Steps
    ///     1. Copy database words_db.
    ///     2. Create a vector index named "words_index" in _default.words collection.
    ///         - expression: "vector"
    ///         - dimensions: 300
    ///         - centroids: 20
    ///         - metric: Euclidean
    ///     3. Check that the index is created without an error returned.
    ///     4. Create an SQL++ query.
    ///         - SELECT meta().id, word, vector_distance(words_index)
    ///           FROM _default.words
    ///           WHERE vector_match(words_index, <dinner vector>, 20)
    ///     5. Check the explain() result of the query to ensure that the "words_index" is used.
    ///     6. Execute the query and check that 20 results are returned and the distance value is more than zero.

    func testCreateVectorIndexWithEuclideanDistance() throws {
        let collection = try db.collection(name: "words")!
        
        var config = VectorIndexConfiguration(expression: "vector", dimensions: 300, centroids: 20)
        config.metric = .euclidean
        try collection.createIndex(withName: "words_index", config: config)
        
        let names = try collection.indexes()
        XCTAssert(names.contains("words_index"))
        
        // Query:
        let sql = "select meta().id, word, vector_distance(words_index) from _default.words where vector_match(words_index, $vector, 20)"
        let parameters = Parameters()
        parameters.setValue(dinnerVector, forName: "vector")
        
        let q = try self.db.createQuery(sql)
        q.parameters = parameters
        
        let explain = try q.explain() as NSString
        XCTAssertNotEqual(explain.range(of: "SCAN kv_.words:vector:words_index").location, NSNotFound)
        
        var rs: ResultSet = try q.execute()
        XCTAssertEqual(rs.allResults().count, 20)
        
        for result in rs.allResults() {
            XCTAssert(result.double(at: 3) > 0)
        }
    }
    
    /// 19. TestCreateVectorIndexWithExistingName
    /// Description
    ///     Test that creating a new vector index with an existing name is fine if the index configuration is the same or not.
    /// Steps
    ///     1. Copy database words_db.
    ///     2. Create a vector index named "words_index" in _default.words collection.
    ///         - expression: "vector"
    ///         - dimensions: 300
    ///         - centroids: 20
    ///     3. Check that the index is created without an error returned.
    ///     4. Repeat step 2 and check that the index is created without an error returned.
    ///     5. Create a vector index named "words_index" in _default.words collection.
    ///         - expression: "vectors"
    ///         - dimensions: 300
    ///         - centroids: 20
    ///     6. Check that the index is created without an error returned.

    func testCreateVectorIndexWithExistingName() throws {
        let collection = try db.collection(name: "words")!
        
        // Create and recreate vector index using the same config
        let config1 = VectorIndexConfiguration(expression: "vector", dimensions: 300, centroids: 20)
        try collection.createIndex(withName: "words_index", config: config1)
        try collection.createIndex(withName: "words_index", config: config1)
        
        // Recreate index with same name using different config
        let config2 = VectorIndexConfiguration(expression: "vectors", dimensions: 300, centroids: 20)
        try collection.createIndex(withName: "words_index", config: config2)
    }
    
    /// 20. TestDeleteVectorIndex
    /// Description
    ///     Test that creating a new vector index with an existing name is fine if the index configuration is the same. Otherwise, an error will be returned.
    /// Steps
    ///     1. Copy database words_db.
    ///     2. Create a vector index named "words_index" in _default.words collection.
    ///         - expression: "vectors"
    ///         - dimensions: 300
    ///        - centroids: 20
    ///     3. Check that the index is created without an error returned.
    ///     4. Create an SQL++ query.
    ///         - SELECT meta().id, word
    ///           FROM _default.words
    ///          WHERE vector_match(words_index, <dinner vector>, 20)
    ///     5. Check the explain() result of the query to ensure that the "words_index" is used.
    ///     6. Execute the query and check that 20 results are returned.
    ///     7. Delete index named "words_index".
    ///     8. Check that getIndexes() does not contain "words_index".

    func testDeleteVectorIndex() throws {
        let collection = try db.collection(name: "words")!
        
        let config = VectorIndexConfiguration(expression: "vector", dimensions: 300, centroids: 20)
        try collection.createIndex(withName: "words_index", config: config)
        
        var names = try collection.indexes()
        XCTAssert(names.contains("words_index"))
        
        // Query:
        let sql = "select meta().id, word from _default.words where vector_match(words_index, $vector, 20)"
        let parameters = Parameters()
        parameters.setValue(dinnerVector, forName: "vector")
        
        let q = try self.db.createQuery(sql)
        q.parameters = parameters
        
        let explain = try q.explain() as NSString
        XCTAssertNotEqual(explain.range(of: "SCAN kv_.words:vector:words_index").location, NSNotFound)
        
        var rs: ResultSet = try q.execute()
        XCTAssertEqual(rs.allResults().count, 20)
        
        try collection.deleteIndex(forName: "words_index")
        names = try collection.indexes()
        XCTAssertFalse(names.contains("words_index"))
    }
    

    /// 21. TestVectorMatchOnNonExistingIndex
    /// Description
    ///     Test that an error will be returned when creating a vector match query that uses a non existing index.
    /// Steps
    ///     1. Copy database words_db.
    ///     2. Create an SQL++ query.
    ///         - SELECT meta().id, word
    ///           FROM _default.words
    ///           WHERE vector_match(words_index, <dinner vector>, 20)
    ///     3. Check that a CouchbaseLiteException is returned as the index doesn’t exist.

    func testVectorMatchOnNonExistingIndex() throws {
        self.expectError(domain: CBLErrorDomain, code: CBLError.missingIndex) {
            let sql = "select meta().id, word from _default.words where vector_match(words_index, $vector, 20)"
            _ = try self.db.createQuery(sql)
        }
    }
    
    /// 22. TestVectorMatchDefaultLimit
    /// Description
    ///     Test that the number of rows returned is limited to the default value which is 3 when using the vector_match query without the limit number specified.
    /// Steps
    ///     1. Copy database words_db.
    ///     2. Create a vector index named "words_index" in _default.words collection.
    ///         - expression: "vector"
    ///         - dimensions: 300
    ///         - centroids: 20
    ///     3. Check that the index is created without an error returned.
    ///     4. Create an SQL++ query.
    ///         - SELECT meta().id, word
    ///           FROM _default.words
    ///           WHERE vector_match(words_index, <dinner vector>)
    ///     5. Check the explain() result of the query to ensure that the "words_index" is used.
    ///     6. Execute the query and check that 3 results are returned.

    func testVectorMatchDefaultLimit() throws {
        let collection = try db.collection(name: "words")!
        
        let config = VectorIndexConfiguration(expression: "vector", dimensions: 300, centroids: 20)
        try collection.createIndex(withName: "words_index", config: config)
        
        var names = try collection.indexes()
        XCTAssert(names.contains("words_index"))
        
        // Query:
        let sql = "select meta().id, word from _default.words where vector_match(words_index, $vector)"
        let parameters = Parameters()
        parameters.setValue(dinnerVector, forName: "vector")
        
        let q = try self.db.createQuery(sql)
        q.parameters = parameters
        
        let explain = try q.explain() as NSString
        XCTAssertNotEqual(explain.range(of: "SCAN kv_.words:vector:words_index").location, NSNotFound)
        
        var rs: ResultSet = try q.execute()
        XCTAssertEqual(rs.allResults().count, 3)
    }
    
    /// 23. TestVectorMatchLimitBoundary
    /// Description
    ///     Test vector_match’s limit boundary which is between 1 - 10000 inclusively. When creating vector_match queries with an out-out-bound limit, an error should be returned.
    /// Steps
    ///     1. Copy database words_db.
    ///     2. Create a vector index named "words_index" in _default.words collection.
    ///         - expression: "vector"
    ///         - dimensions: 300
    ///         - centroids: 20
    ///     3. Check that the index is created without an error returned.
    ///     4. Create an SQL++ query.
    ///         - SELECT meta().id, word
    ///           FROM _default.words
    ///          WHERE vector_match(words_index, <dinner vector>, <limit>)
    ///         - limit: 1 and 10000
    ///     5. Check that the query can be created without an error.
    ///     6. Repeat step 4 with the limit: -1, 0, and 10001
    ///     7. Check that a CouchbaseLiteException is returned when creating the query.

    func testVectorMatchLimitBoundary() throws {
        let collection = try db.collection(name: "words")!
        
        let config = VectorIndexConfiguration(expression: "vector", dimensions: 300, centroids: 20)
        try collection.createIndex(withName: "words_index", config: config)
        
        var names = try collection.indexes()
        XCTAssert(names.contains("words_index"))
        
        // Check valid query with 1 and 10000 set limit
        for limit in [1, 10000] {
            let sql = "select meta().id, word from _default.words where vector_match(words_index, $vector, \(limit))"
            _ = try self.db.createQuery(sql)
        }
        
        // Check if error thrown for wrong limit values
        for limit in [-1, 0, 10001] {
            self.expectError(domain: CBLErrorDomain, code: CBLError.invalidQuery) {
                let sql = "select meta().id, word from _default.words where vector_match(words_index, $vector, \(limit)"
                _ = try self.db.createQuery(sql)
            }
        }
    }
    
    /// 24. TestVectorMatchWithAndExpression
    /// Description
    ///     Test that vector_match can be used in AND expression.
    /// Steps
    ///     1. Copy database words_db.
    ///     2. Create a vector index named "words_index" in _default.words collection.
    ///         - expression: "vector"
    ///         - dimensions: 300
    ///        - centroids: 20
    ///     3. Check that the index is created without an error returned.
    ///     4. Create an SQL++ query.
    ///         - SELECT word, catid
    ///           FROM _default.words
    ///           WHERE vector_match(words_index, <dinner vector>, 300) AND catid = 'cat1'
    ///     5. Check that the query can be created without an error.
    ///     6. Check the explain() result of the query to ensure that the "words_index" is used.
    ///     7. Execute the query and check that the number of results returned is 50 (there are 50 words in catid=1), and the results contain only catid == 'cat1'.
 
    func testVectorMatchWithAndExpression() throws {
        let collection = try db.collection(name: "words")!
        
        let config = VectorIndexConfiguration(expression: "vector", dimensions: 300, centroids: 20)
        try collection.createIndex(withName: "words_index", config: config)
        
        var names = try collection.indexes()
        XCTAssert(names.contains("words_index"))
        
        // Query with a single AND:
        let sql = "select word, catid from _default.words where vector_match(words_index, $vector, 300) AND catid = 'cat1'"
        let parameters = Parameters()
        parameters.setValue(dinnerVector, forName: "vector")
        
        let q = try self.db.createQuery(sql)
        q.parameters = parameters
        
        let explain = try q.explain() as NSString
        XCTAssertNotEqual(explain.range(of: "SCAN kv_.words:vector:words_index").location, NSNotFound)
        
        var rs: ResultSet = try q.execute()
        XCTAssertEqual(rs.allResults().count, 50)
        
        for result in rs.allResults() {
            XCTAssertEqual(result.value(at: 1) as! String, "cat1")
        }
    }
    
    /// 25. TestVectorMatchWithMultipleAndExpression
    /// Description
    ///     Test that vector_match can be used in multiple AND expressions.
    /// Steps
    ///     1. Copy database words_db.
    ///     2. Create a vector index named "words_index" in _default.words collection.
    ///         - expression: "vector"
    ///         - dimensions: 300
    ///         - centroids: 20
    ///     3. Check that the index is created without an error returned.
    ///     4. Create an SQL++ query.
    ///         - SELECT word, catid
    ///           FROM _default.words
    ///           WHERE (vector_match(words_index, <dinner vector>, 300) AND word is valued) AND catid = 'cat1'
    ///     5. Check that the query can be created without an error.
    ///     6. Check the explain() result of the query to ensure that the "words_index" is used.
    ///     7. Execute the query and check that the number of results returned is 50 (there are 50 words in catid=1), and the results contain only catid == 'cat1'.

    func testVectorMatchWithMultipleAndExpression() throws {
        let collection = try db.collection(name: "words")!
        
        let config = VectorIndexConfiguration(expression: "vector", dimensions: 300, centroids: 20)
        try collection.createIndex(withName: "words_index", config: config)
        
        var names = try collection.indexes()
        XCTAssert(names.contains("words_index"))
        
        // Query with mutiple ANDs:
        let sql = "select word, catid from _default.words where (vector_match(words_index, $vector, 300) AND word is valued) AND catid = 'cat1'"
        let parameters = Parameters()
        parameters.setValue(dinnerVector, forName: "vector")
        
        let q = try self.db.createQuery(sql)
        q.parameters = parameters
        
        let explain = try q.explain() as NSString
        XCTAssertNotEqual(explain.range(of: "SCAN kv_.words:vector:words_index").location, NSNotFound)
        
        var rs: ResultSet = try q.execute()
        XCTAssertEqual(rs.allResults().count, 50)
        
        for result in rs.allResults() {
            XCTAssertEqual(result.value(at: 1) as! String, "cat1")
        }
    }
    

    /// 26. TestInvalidVectorMatchWithOrExpression
    /// Description
    ///     Test that vector_match cannot be used with OR expression.
    /// Steps
    ///     1. Copy database words_db.
    ///     2. Create a vector index named "words_index" in _default.words collection.
    ///         - expression: "vector"
    ///         - dimensions: 300
    ///         - centroids: 20
    ///     3. Check that the index is created without an error returned.
    ///     4. Create an SQL++ query.
    ///         - SELECT word, catid
    ///           FROM _default.words
    ///           WHERE vector_match(words_index, <dinner vector>, 20) OR catid = 1
    ///     5. Check that a CouchbaseLiteException is returned when creating the query.

    func testInvalidVectorMatchWithOrExpression() throws {
        let collection = try db.collection(name: "words")!
        
        let config = VectorIndexConfiguration(expression: "vector", dimensions: 300, centroids: 20)
        try collection.createIndex(withName: "words_index", config: config)
        
        var names = try collection.indexes()
        XCTAssert(names.contains("words_index"))
        
        // Query with OR:
        let sql = "select meta().id, word, catid from _default.words where vector_match(words_index, $vector, 300) OR catid = 'cat1'"
        self.expectError(domain: CBLErrorDomain, code: CBLError.invalidQuery) {
            _ = try self.db.createQuery(sql)
        }
    }
}
