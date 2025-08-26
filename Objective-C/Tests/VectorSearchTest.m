//
//  VectorIndexTest.m
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

#ifdef COUCHBASE_ENTERPRISE

#import "VectorSearchTest.h"
#import "CBLWordEmbeddingModel.h"
#import "CBLTestCustomLogSink.h"

#define kDinnerVector @[@0.03193166106939316, @0.032055653631687164, @0.07188114523887634, @(-0.09893740713596344), @(-0.07693558186292648), @0.07570040225982666, @0.42786234617233276, @(-0.11442682892084122), @(-0.7863243818283081), @(-0.47983086109161377), @(-0.10168658196926117), @0.10985997319221497, @(-0.15261511504650116), @(-0.08458329737186432), @(-0.16363860666751862), @(-0.20225222408771515), @(-0.2593214809894562), @(-0.032738097012043), @(-0.16649988293647766), @(-0.059701453894376755), @0.17472036182880402, @(-0.007310086861252785), @(-0.13918264210224152), @(-0.07260780036449432), @(-0.02461239881813526), @(-0.04195880889892578), @(-0.15714778006076813), @0.48038315773010254, @0.7536261677742004, @0.41809454560279846, @(-0.17144775390625), @0.18296195566654205, @(-0.10611499845981598), @0.11669538915157318, @0.07423929125070572, @(-0.3105475902557373), @(-0.045081984251737595), @(-0.18190748989582062), @0.22430984675884247, @0.05735112354159355, @(-0.017394868656992912), @(-0.148889422416687), @(-0.20618586242198944), @(-0.1446581482887268), @0.061972495168447495, @0.07787969708442688, @0.14225411415100098, @0.20560632646083832, @0.1786964386701584, @(-0.380594402551651), @(-0.18301603198051453), @(-0.19542981684207916), @0.3879885971546173, @(-0.2219538390636444), @0.11549852043390274, @(-0.0021717497147619724), @(-0.10556972026824951), @0.030264658853411674, @0.16252967715263367, @0.06010117009282112, @(-0.045007310807704926), @0.02435707487165928, @0.12623260915279388, @(-0.12688252329826355), @(-0.3306281864643097), @0.06452160328626633,@0.0707000121474266, @(-0.04959108680486679), @(-0.2567063570022583), @(-0.01878536120057106), @(-0.10857286304235458), @(-0.01754194125533104), @(-0.0713721290230751), @0.05946013703942299, @(-0.1821729987859726), @(-0.07293688505887985), @(-0.2778160572052002), @0.17880073189735413, @(-0.04669278487563133), @0.05351974070072174, @(-0.23292849957942963), @0.05746332183480263, @0.15462779998779297, @(-0.04772235080599785), @(-0.003306782804429531), @0.058290787041187286, @0.05908169597387314, @0.00504430802538991, @(-0.1262340396642685), @0.11612161248922348, @0.25303348898887634, @0.18580256402492523, @0.09704313427209854, @(-0.06087183952331543), @0.19697663187980652, @(-0.27528849244117737), @(-0.0837797075510025), @(-0.09988483041524887), @(-0.20565757155418396), @0.020984146744012833, @0.031014855951070786, @0.03521743416786194, @(-0.05171370506286621), @0.009112107567489147, @(-0.19296088814735413), @(-0.19363830983638763), @0.1591167151927948, @(-0.02629968523979187), @(-0.1695055067539215), @(-0.35807400941848755), @(-0.1935291737318039), @(-0.17090126872062683), @(-0.35123637318611145), @(-0.20035606622695923), @(-0.03487539291381836), @0.2650701701641083, @(-0.1588021069765091), @0.32268261909484863, @(-0.024521857500076294), @(-0.11985184997320175), @0.14826008677482605, @0.194917231798172, @0.07971998304128647, @0.07594677060842514, @0.007186363451182842, @(-0.14641280472278595), @0.053229596465826035, @0.0619836151599884, @0.003207010915502906, @(-0.12729716300964355), @0.13496214151382446, @0.107656329870224, @(-0.16516226530075073), @(-0.033881571143865585), @(-0.11175122112035751), @(-0.005806141998618841), @(-0.4765360355377197), @0.11495379358530045, @0.1472187340259552, @0.3781401813030243, @0.10045770555734634, @(-0.1352398842573166), @(-0.17544329166412354), @(-0.13191302120685577), @(-0.10440415143966675), @0.34598618745803833, @0.09728766977787018, @(-0.25583627820014954), @0.035236816853284836, @0.16205145418643951, @(-0.06128586828708649), @0.13735555112361908, @0.11582338809967041, @(-0.10182418674230576), @0.1370954066514969, @0.15048766136169434, @0.06671152263879776, @(-0.1884871870279312), @(-0.11004580557346344), @0.24694739282131195, @(-0.008159132674336433), @(-0.11668405681848526), @(-0.01214478351175785), @0.10379738360643387, @(-0.1626262664794922), @0.09377897530794144, @0.11594484746456146, @(-0.19621512293815613), @0.26271334290504456, @0.04888357222080231, @(-0.10103251039981842), @0.33250945806503296, @0.13565145432949066, @(-0.23888370394706726), @(-0.13335271179676056), @(-0.0076894499361515045), @0.18256276845932007, @0.3276212215423584, @(-0.06567271053791046), @(-0.1853761374950409), @0.08945729583501816, @0.13876311480998993, @0.09976287186145782, @0.07869105041027069, @(-0.1346970647573471), @0.29857659339904785, @0.1329529583454132, @0.11350086331367493, @0.09112624824047089, @(-0.12515446543693542), @(-0.07917925715446472), @0.2881546914577484, @(-1.4532661225530319e-05), @(-0.07712751626968384), @0.21063975989818573, @0.10858846455812454, @(-0.009552721865475178), @0.1629313975572586, @(-0.39703384041786194), @0.1904662847518921, @0.18924959003925323, @(-0.09611514210700989), @0.001136621693149209, @(-0.1293390840291977), @(-0.019481558352708817), @0.09661063551902771, @(-0.17659670114517212), @0.11671938002109528, @0.15038564801216125, @(-0.020016824826598167), @(-0.20642194151878357), @0.09050136059522629, @(-0.1768183410167694), @(-0.2891409397125244), @0.04596589505672455, @(-0.004407480824738741), @0.15323616564273834, @0.16503025591373444, @0.17370983958244324, @0.02883041836321354, @0.1463884711265564, @0.14786243438720703, @(-0.026439940556883812), @(-0.03113352134823799), @0.10978181660175323, @0.008928884752094746, @0.24813824892044067, @(-0.06918247044086456), @0.06958142668008804, @0.17475970089435577, @0.04911438003182411, @0.17614248394966125, @0.19236832857131958, @(-0.1425514668226242), @(-0.056531358510255814), @(-0.03680772706866264), @(-0.028677923604846), @(-0.11353116482496262), @0.012293893843889236, @(-0.05192646384239197), @0.20331953465938568, @0.09290937334299088, @0.15373043715953827, @0.21684466302394867, @0.40546831488609314, @(-0.23753701150417328), @0.27929359674453735, @(-0.07277711480855942), @0.046813879162073135, @0.06883064657449722, @(-0.1033223420381546), @0.15769273042678833, @0.21685580909252167, @(-0.00971329677850008), @0.17375953495502472, @0.027193285524845123, @(-0.09943609684705734), @0.05770351365208626, @0.0868956446647644, @(-0.02671697922050953), @(-0.02979189157485962), @0.024517420679330826, @(-0.03931192681193352), @(-0.35641804337501526), @(-0.10590721666812897), @(-0.2118944674730301), @(-0.22070199251174927), @0.0941486731171608, @0.19881175458431244, @0.1815279871225357, @(-0.1256905049085617), @(-0.0683583989739418), @0.19080783426761627, @(-0.009482398629188538), @(-0.04374842345714569), @0.08184348791837692, @0.20070189237594604, @0.039221834391355515, @(-0.12251003831624985), @(-0.04325549304485321), @0.03840530663728714, @(-0.19840988516807556), @(-0.13591833412647247), @0.03073180839419365, @0.1059495136141777, @(-0.10656466335058212), @0.048937033861875534, @(-0.1362423598766327), @(-0.04138947278261185), @0.10234509408473969, @0.09793911874294281, @0.1391254961490631, @(-0.0906999260187149), @0.146945983171463, @0.14941848814487457, @0.23930180072784424, @0.36049938201904297, @0.0239607822149992, @0.08884347230195999, @0.061145078390836716]

#define kLunchVectorBase64 @"4OYevd8eyDxJGj69HCKOvoCJYTzQCJs9xhDbPp1Y6r2OTEm/ZKz1vtRbwL1Ik8I9+RQFPpyGBD69OEI9ul+evZD71L2nI4y8uTINPnVN+702+c4+8zToPEoGKj6xEqi93vPFvQDdK71Z6yC+yPT1PqXtQD99ENY+xnh+PpBEOD6aIUi+eVezvg24fj0YAJ++46c4vfVFOr57sWU+A+lqPdFq3T1ZJg6+Ok6yvs1/Cr5blju+ITa9vAFxlj1+8h4+c7UePe6fUL6OaDu+wR5IvnGmxj7eR2O+fYrsPf8kw73IOfq8YOJtvAxBMj0g99O8+toTPr0v8r2I4mK+Yxd1PTGxhbzu3aS9zeJEPqKy0Ty2cOy9YqgQPL7af703wFK9965hvOM0pz2VuAc+RIyTu4nxi73pigA9RCjpvVTOFj6zPIC+HTsrvrcpTz4vXzS6ArPxvM+VNL3hJgk+9pM7vtP1jL51sao8q4oJPonfBDxkAiC9XvJUPWiWTD1Kwbe+4KHOvUQmjjypsrS6i4MJPjRnWz0g8E4+Ad3IvVsKMT5O7Qw9X4tFPbpriT1TYme8uw5uvqBar72DLEa+vgAvvkHVs74kKk2+gNkOvZkV57zBfcC+/WM7PrKQQb4+adC9ftEXPmKYRz47RKM9+4mbPZZ76zs4LZq+0gIXPgNoxL26tT09rGFdvPdQqDwi/Y8939OLvYVTQr7J8hK+ljyeveMZsL5xeGi8sppcPfezjT11QuU9cvRpPSoby7yIZ3U9FUPXPd/y1z2xBhu9CfRyvbjXR72xLjk+9rkLvrdWJD2u+Iy9TtM/vlc0Ez4E1ju9XtcrPP+4Cr5ymDu+DfEAPswpP770tKm+3u07vsXxXb19zcC8MQ/APX507T2e7Ei+XYKGPiQ6SD0MORK+Lk4NP1zuHTzrAKW+Eu2WvSGPRj6fL7g9IdSgPkNyojxUSPi95uGqvJugrj0Bqbc9x1eVPk8qh74NlYk+07gZPVqt271XR2E+bMxmOyw0JD1Lg2Y+h+GDvRpuj70YCss890HtPdFwMz7oo7I+RpgXv4/lkz54b+Y8l6yOPdbWYj3H+4G+Q4wXvsXhyD0ayts9XIXBPndXLj34Q1I+0zfQu5pblj66UKa9dSWqvRl1xb04RQK9HsA6PrH2rD2r8wC+XQQPPlSirDwC3zU+K7Z4vUfVML4xHyY92TguPigvMj2emD8+q3AXPsSHWz4Cq5+9P/o7PveDcD095w++4fc9vvE81j17lt09AY7CvHD/Nz7FdCe+t7z4PDJPZD4Qsce9mdwZPtvzDj60sz6+ETvUPTLZ970Gauu83dW7PZZPCj51tCc+yMYtPYrmSjyUcpE+GCDgPf1tGr7aODg+ESYGPmu52T070vi9kW0vvaiwWj6JgQ6+hoehPVygk77JeOg8yCI+PtSnpD2I6w0+z3IFPRUoLD7boxM+XJYbviPzNrxBSBs+XO+WPpkuH74N9+m9tds9PiCinT6BaZ2+tGIfvhZSTj2ZP2k+cld+PHx1Kj4uOfK9bsXHPRx8Bz5OlMg96nYOPuLAub0CeRY+KQEZPogLdT5gk7g+Z0nEPJHztT1Dc3o9"

#pragma mark - Vector Search test
/**
 Test Spec: https://github.com/couchbaselabs/couchbase-lite-api/blob/master/spec/tests/T0001-Vector-Search.md
*/

@implementation VectorSearchTest {
    CBLTestCustomLogSink* _logSink;
    
    CBLDatabase* _wordDB;
    CBLDatabase* _modelDB;
    
    // For some reason the autorelease poll could run after the teardown is called.
    // To avoid leaking check issue, lazy creating these from the tests.
    CBLCollection* _wordsCollection;
    CBLCollection* _extWordsCollection;
}

@synthesize wordDB=_wordDB;

- (CBLCollection*) wordsCollection {
    if (!_wordsCollection) {
        _wordsCollection = [_wordDB collectionWithName: kWordsCollectionName scope: nil error: nil];
    }
    return _wordsCollection;
}

- (CBLCollection*) extWordsCollection {
    if (!_extWordsCollection) {
        _extWordsCollection = [_wordDB collectionWithName: kExtWordsCollectionName scope: nil error: nil];
    }
    return _extWordsCollection;
}

- (void) setUp {
    [self deleteDBNamed: kWordsDatabaseName error: nil];
    
    [super setUp];

    NSError* error;
    Assert([CBLExtension enableVectorSearch: &error]);
    
    CBLDatabaseConfiguration* config = [[CBLDatabaseConfiguration alloc] init];
    config.directory = self.directory;
    
    NSString* path = [self databasePath: @"words_db.cblite2" inDirectory: @"vectorsearch"];
    Assert([CBLDatabase copyFromPath:path toDatabase: kWordsDatabaseName withConfig: config error: &error]);
    
    _wordDB = [self openDBNamed: kWordsDatabaseName error: &error];
    AssertNotNil(_wordDB);
    
    _logSink = [[CBLTestCustomLogSink alloc] init];
    CBLLogSinks.custom = [[CBLCustomLogSink alloc] initWithLevel: kCBLLogLevelInfo logSink: _logSink];
}

- (void) tearDown {
    CBLLogSinks.custom = nil;
    
    _wordsCollection = nil;
    _extWordsCollection = nil;
    
    NSError* error;
    if (_wordDB) {
        Assert([_wordDB close: &error], @"Failed to close db: %@", error);
        _wordDB = nil;
    }
    
    if (_modelDB) {
        Assert([_modelDB close: &error], @"Failed to close db: %@", error);
        _modelDB = nil;
    }
    
    [self unregisterPredictiveModel];
    
    [super tearDown];
}

- (void) registerPredictiveModel {
    if (!_modelDB) {
        _modelDB = [self openDBNamed: kWordsDatabaseName error: nil];
        AssertNotNil(_modelDB);
    }
    
    CBLWordEmbeddingModel* model = [[CBLWordEmbeddingModel alloc] initWithDatabase: _modelDB];
    [CBLDatabase.prediction registerModel: model withName: kWordPredictiveModelName];
}

- (void) unregisterPredictiveModel {
    [CBLDatabase.prediction unregisterModelWithName: kWordPredictiveModelName];
}

- (void) resetIndexWasTrainedLog {
    [_logSink reset];
}

- (BOOL) checkIndexWasTrained {
    return ![_logSink containsString: @"Untrained index; queries may be slow"];
}

- (void) createVectorIndexInCollection: (CBLCollection*)collection 
                                  name: (NSString*)name
                                config: (CBLVectorIndexConfiguration*)config {
    Assert([collection createIndexWithName: name config: config error: nil]);
    Assert([[collection indexes: nil] containsObject: name]);
}

- (void) createWordsIndexWithConfig: (CBLVectorIndexConfiguration*)config {
    [self createVectorIndexInCollection: self.wordsCollection name: kWordsIndexName config: config];
}

- (void) deleteWordsIndex {
    Assert([_wordsCollection deleteIndexWithName: kWordsIndexName error: nil]);
    AssertFalse([[self.wordsCollection indexes: nil] containsObject: @"words_index"]);
}

- (NSString*) wordsQueryDefaultExpression {
    return @"vector";
}

- (NSString*) wordsQueryStringWithLimit: (NSInteger)limit
                                 metric: (nullable NSString*)metric
                       vectorExpression: (nullable NSString*)vectorExpression
                            whereClause: (nullable NSString*)whereClause {
    NSString* sql = [NSString stringWithFormat: @"SELECT meta().id, word, catid FROM %@ ", kWordsCollectionName];
    
    if (whereClause) {
        sql = [sql stringByAppendingFormat: @"WHERE %@ ", whereClause];
    }
    
    if (!vectorExpression) {
        vectorExpression = [self wordsQueryDefaultExpression];
    }
    
    if (metric) {
        sql = [sql stringByAppendingFormat: @"ORDER BY APPROX_VECTOR_DISTANCE(%@, $vector, \"%@\") ", vectorExpression, metric];
    } else {
        sql = [sql stringByAppendingFormat: @"ORDER BY APPROX_VECTOR_DISTANCE(%@, $vector) ", vectorExpression];
    }
    
    sql = [sql stringByAppendingFormat: @"LIMIT %ld", (long)limit];

    return sql;
}

- (NSString*) wordsQueryStringWithLimit: (NSInteger)limit {
    return [self wordsQueryStringWithLimit: limit metric: nil vectorExpression: nil whereClause: nil];
}

- (CBLQueryResultSet*) executeWordsQueryWithLimit: (NSInteger)limit
                                           metric: (NSString*)metric
                                 vectorExpression: (NSString*)vectorExpression
                                      whereClause: (NSString*)whereClause
                                    checkTraining: (BOOL) checkTraining {
    NSError* error;
    NSString* sql = [self wordsQueryStringWithLimit: limit 
                                             metric: metric
                                   vectorExpression: vectorExpression 
                                        whereClause: whereClause];
    CBLQuery* query = [_wordDB createQuery: sql error: &error];
    AssertNotNil(query);
    
    CBLQueryParameters* parameters = [[CBLQueryParameters alloc] init];
    [parameters setValue: kDinnerVector forName: @"vector"];
    [query setParameters: parameters];
    
    NSString* explain = [query explain: &error];
    Assert([explain rangeOfString: @"kv_.words:vector:words_index"].location != NSNotFound);
    
    CBLQueryResultSet* rs = [query execute: &error];
    AssertNotNil(rs);
    
    if (checkTraining) {
        XCTAssert([self checkIndexWasTrained]);
    }
    
    return rs;
}

- (CBLQueryResultSet*) executeWordsQueryWithLimit: (NSInteger)limit {
    return [self executeWordsQueryWithLimit: limit
                                     metric: nil
                           vectorExpression: nil
                                whereClause: nil
                              checkTraining: true];
}

- (CBLQueryResultSet*) executeWordsQueryNoTrainingCheckWithLimit: (NSInteger)limit {
    return [self executeWordsQueryWithLimit: limit
                                     metric: nil
                           vectorExpression: nil
                                whereClause: nil
                              checkTraining: false];
}

- (NSDictionary<NSString*, NSString*>*) toDocIDWordMap: (CBLQueryResultSet*)resultSet {
    NSMutableDictionary<NSString*, NSString*>* wordMap = [NSMutableDictionary dictionary];
    for (CBLQueryResult* result in resultSet) {
        NSString* docID = [result stringAtIndex: 0];
        NSString* word = [result stringAtIndex: 1];
        wordMap[docID] = word;
    }
    return wordMap;
}

@end

/**
 * Test Spec:
 * https://github.com/couchbaselabs/couchbase-lite-api/blob/master/spec/tests/T0001-Vector-Search.md
 *
 * Version: 2.1.0
 */
@interface VectorSearchTest_Main : VectorSearchTest

@end

@implementation VectorSearchTest_Main

/**
 * 1. TestVectorIndexConfigurationDefaultValue
 * Description
 *     Test that the VectorIndexConfiguration has all default values returned as expected.
 * Steps
 *     1. Create a VectorIndexConfiguration object.
 *         - expression: "vector"
 *         - dimensions: 300
 *         - centroids: 8
 *     2. Get and check the following property values:
 *         - encoding: 8-Bit Scalar Quantizer Encoding
 *         - metric: Euclidean Distance
 *         - minTrainingSize: 0
 *         - maxTrainingSize: 0
 *     3. To check the encoding type, platform code will have to expose some internal
 *        property to the tests for verification.
 */
- (void) testVectorIndexConfigurationDefaultValue {
    CBLVectorIndexConfiguration* config = VECTOR_INDEX_CONFIG(@"vector", 300, 8);
    AssertEqualObjects(config.encoding, [CBLVectorEncoding scalarQuantizerWithType: kCBLSQ8]);
    AssertEqual(config.metric, kCBLDistanceMetricEuclideanSquared);
    AssertEqual(config.minTrainingSize, 0);
    AssertEqual(config.maxTrainingSize, 0);
    AssertEqual(config.numProbes, 0);
}

/**
 * 2. TestVectorIndexConfigurationSettersAndGetters
 * Description
 *     Test that all getters and setters of the VectorIndexConfiguration work as expected.
 * Steps
 *     1. Create a VectorIndexConfiguration object with the following properties.
 *         - expression: "vector"
 *         - dimensions: 300
 *         - centroids: 8
 *         - encoding: None
 *         - metric: Cosine Distance
 *         - minTrainingSize: 100
 *         - maxTrainingSize: 200
 *     2. Get and check the following properties.
 *         - expression: "vector"
 *         - expressions: ["vector"]
 *         - dimensions: 300
 *         - centroids: 20
 *         - encoding: None
 *         - metric: Cosine
 *         - minTrainingSize: 100
 *         - maxTrainingSize: 200
 */
- (void) testVectorIndexConfigurationSettersAndGetters {
    CBLVectorIndexConfiguration* config = VECTOR_INDEX_CONFIG(@"vector", 300, 8);
    CBLVectorEncoding* noneEncoding = [CBLVectorEncoding none];
    config.encoding = noneEncoding;
    config.metric = kCBLDistanceMetricCosine;
    config.minTrainingSize = 100;
    config.maxTrainingSize = 200;
    
    AssertEqual(config.expression, @"vector");
    AssertEqualObjects(config.expressions, @[@"vector"]);
    AssertEqual(config.dimensions, 300);
    AssertEqual(config.centroids, 8);
    AssertEqual(config.encoding, noneEncoding);
    AssertEqual(config.metric, kCBLDistanceMetricCosine);
    AssertEqual(config.minTrainingSize, 100);
    AssertEqual(config.maxTrainingSize, 200);
}

/**
 * 3. TestDimensionsValidation
 * Description
 *     Test that the dimensions are validated correctly. The invalid argument exception
 *     should be thrown when creating vector index configuration objects with invalid
 *     dimensions.
 * Steps
 *     1. Create a VectorIndexConfiguration object.
 *         - expression: "vector"
 *         - dimensions: 2 and 4096
 *         - centroids: 8
 *     2. Check that the config can be created without an error thrown.
 *     3. Use the config to create the index and check that the index
 *       can be created successfully.
 *     4. Change the dimensions to 1 and 4097.
 *     5. Check that an invalid argument exception is thrown.
 */
- (void) testDimensionsValidation {
    [self createWordsIndexWithConfig: VECTOR_INDEX_CONFIG(@"vector", 2, 8)];
    
    [self createWordsIndexWithConfig: VECTOR_INDEX_CONFIG(@"vector", 4096, 8)];
    
    [self expectException: NSInvalidArgumentException in:^{
        VECTOR_INDEX_CONFIG(@"vector", 1, 8);
    }];
    
    [self expectException: NSInvalidArgumentException in:^{
        VECTOR_INDEX_CONFIG(@"vector", 4097, 8);
    }];
}

/**
 * 4. TestCentroidsValidation
 * Description
 *     Test that the centroids value is validated correctly. The invalid argument
 *     exception should be thrown when creating vector index configuration objects with
 *     invalid centroids..
 * Steps
 *     1. Create a VectorIndexConfiguration object.
 *         - expression: "vector"
 *         - dimensions: 300
 *         - centroids: 1 and 64000
 *     2. Check that the config can be created without an error thrown.
 *     3. Use the config to create the index and check that the index
 *        can be created successfully.
 *     4. Change the centroids to 0 and 64001.
 *     5. Check that an invalid argument exception is thrown.
 */
- (void) testCentroidsValidation {
    CBLVectorIndexConfiguration* config1 = VECTOR_INDEX_CONFIG(@"vector", 300, 1);
    Assert([self.wordsCollection createIndexWithName: @"words_index_1" config: config1 error: nil]);

    CBLVectorIndexConfiguration* config2 = VECTOR_INDEX_CONFIG(@"vector", 300, 64000);
    Assert([self.wordsCollection createIndexWithName: @"words_index_2" config: config2 error: nil]);
    
    [self expectException: NSInvalidArgumentException in:^{
        (void) VECTOR_INDEX_CONFIG(@"vector", 300, 0);
    }];
    
    [self expectException: NSInvalidArgumentException in:^{
        (void) VECTOR_INDEX_CONFIG(@"vector", 300, 64001);
    }];
}

/**
 * 5. TestCreateVectorIndex
 * Description
 *     Using the default configuration, test that the vector index can be created from
 *     the embedded vectors in the documents. The test also verifies that the created
 *     index can be used in the query.
 * Steps
 *     1. Copy database words_db.
 *     2. Register a custom logger to capture the INFO log.
 *     3. Create a vector index named "words_index" in _default.words collection.
 *         - expression: "vector"
 *         - dimensions: 300
 *         - centroids: 20
 *     4. Check that the index is created without an error returned.
 *     5. Get index names from the _default.words collection and check that the index
 *       names contains “words_index”.
 *     6. Create an SQL++ query:
 *         - SELECT meta().id, word
 *           FROM _default.words
 *           ORDER BY APPROX_VECTOR_DISTANCE(vector, $dinerVector)
 *           LIMIT 20
 *     7. Check the explain() result of the query to ensure that the "words_index" is used.
 *     8. Execute the query and check that 20 results are returned.
 *     9. Verify that the index was trained by checking that the “Untrained index; queries may be slow” 
 *       doesn’t exist in the log.
 *     10. Reset the custom logger.
 */
- (void) testCreateVectorIndex {
    [self createWordsIndexWithConfig: VECTOR_INDEX_CONFIG(@"vector", 300, 8)];
    
    CBLQueryResultSet* rs = [self executeWordsQueryWithLimit: 20];
    AssertEqual(rs.allObjects.count, 20);
}

/**
 * 6. TestUpdateVectorIndex
 * Description
 *     Test that the vector index created from the embedded vectors will be updated
 *     when documents are changed. The test also verifies that the created index can be
 *     used in the query.
 * Steps
 *     1. Copy database words_db.
 *     2. Register a custom logger to capture the INFO log.
 *     3. Create a vector index named "words_index" in _default.words collection.
 *         - expression: "vector"
 *         - dimensions: 300
 *         - centroids: 8
 *     4. Check that the index is created without an error returned.
 *     5. Create an SQL++ query:
 *         - SELECT meta().id, word
 *           FROM _default.words
 *           WHERE vector_match(words_index, <dinner vector>)
 *           LIMIT 350
 *     6. Check the explain() result of the query to ensure that the "words_index" is used.
 *     7. Execute the query and check that 300 results are returned.
 *     8. Verify that the index was trained by checking that the “Untrained index; queries may be slow” 
 *       doesn’t exist in the log.
 *     9. Update the documents:
 *         - Create _default.words.word301 with the content from _default.extwords.word1
 *         - Create _default.words.word302 with the content from _default.extwords.word2
 *         - Update _default.words.word1 with the content from _default.extwords.word3
 *         - Delete _default.words.word2
 *     10. Execute the query again and check that 301 results are returned, and
 *         - word301 and word302 are included.
 *         - word1’s word is updated with the word from _default.extwords.word3
 *         - word2 is not included.
 *     11. Reset the custom logger.
 */
- (void) testUpdateVectorIndex {
    [self createWordsIndexWithConfig: VECTOR_INDEX_CONFIG(@"vector", 300, 8)];
    
    CBLQueryResultSet* rs = [self executeWordsQueryWithLimit: 350];
    AssertEqual(rs.allObjects.count, 300);
    
    // Update docs:
    NSError* error;
    CBLDocument* extWord1 = [self.extWordsCollection documentWithID: @"word1" error : &error];
    CBLMutableDocument* word301 = [self createDocument: @"word301" data: [extWord1 toDictionary]];
    Assert([self.wordsCollection saveDocument: word301 error: &error]);
    
    CBLDocument* extWord2 = [self.extWordsCollection documentWithID: @"word2" error : &error];
    CBLMutableDocument* word302 = [self createDocument: @"word302" data: [extWord2 toDictionary]];
    Assert([self.wordsCollection saveDocument: word302 error: &error]);
    
    CBLDocument* extWord3 = [self.extWordsCollection documentWithID: @"word3" error : &error];
    CBLMutableDocument* word1 = [[self.wordsCollection documentWithID: @"word1" error: &error] toMutable];
    [word1 setData: [extWord3 toDictionary]];
    Assert([self.wordsCollection saveDocument: word1 error: &error]);
    
    [self.wordsCollection deleteDocument: [self.wordsCollection documentWithID: @"word2" error :&error] error: &error];
    
    rs = [self executeWordsQueryWithLimit: 350];
    NSDictionary<NSString*, NSString*>* wordMap = [self toDocIDWordMap: rs];
    AssertEqual(wordMap.count, 301);
    AssertEqualObjects(wordMap[@"word301"], [word301 stringForKey: @"word"]);
    AssertEqualObjects(wordMap[@"word302"], [word302 stringForKey: @"word"]);
    AssertEqualObjects(wordMap[@"word1"], [word1 stringForKey: @"word"]);
    AssertNil(wordMap[@"word2"]);
}

/**
 * 7. TestCreateVectorIndexWithInvalidVectors
 * Description
 *     Using the default configuration, test that when creating the vector index with
 *     invalid vectors, the invalid vectors will be skipped from indexing.
 * Steps
 *     1. Copy database words_db.
 *     2. Register a custom logger to capture the INFO log.
 *     3. Update documents:
 *         - Update _default.words word1 with "vector" = null
 *         - Update _default.words word2 with "vector" = "string"
 *         - Update _default.words word3 by removing the "vector" key.
 *         - Update _default.words word4 by removing one number from the "vector" key.
 *     4. Create a vector index named "words_index" in _default.words collection.
 *         - expression: "vector"
 *         - dimensions: 300
 *         - centroids: 8
 *     5. Check that the index is created without an error returned.
 *     6. Create an SQL++ query.
 *         - SELECT meta().id, word
 *           FROM _default.words
 *           ORDER BY APPROX_VECTOR_DISTANCE(vector, $dinerVector)
 *           LIMIT 350
 *     7. Execute the query and check that 296 results are returned, and the results
 *        do not include document word1, word2, word3, and word4.
 *     8. Verify that the index was trained by checking that the “Untrained index; queries may be slow” 
 *       doesn’t exist in the log.
 *     9. Update an already index vector with an invalid vector.
 *         - Update _default.words word5 with "vector" = null.
 *     10. Execute the query and check that 295 results are returned, and the results
 *        do not include document word5.
 *     11. Reset the custom logger.
 */
- (void) testCreateVectorIndexWithInvalidVectors {
    NSError* error;
    
    // Update docs:
    CBLMutableDocument* auxDoc = [[self.wordsCollection documentWithID: @"word1" error: &error] toMutable];
    [auxDoc setArray: nil forKey: @"vector"];
    [self.wordsCollection saveDocument: auxDoc error: &error];
    
    auxDoc = [[self.wordsCollection documentWithID: @"word2" error: &error] toMutable];
    [auxDoc setString: @"string" forKey: @"vector"];
    [self.wordsCollection saveDocument: auxDoc error: &error];
    
    auxDoc = [[self.wordsCollection documentWithID: @"word3" error: &error] toMutable];
    [auxDoc removeValueForKey: @"vector"];
    [self.wordsCollection saveDocument: auxDoc error: &error];
    
    auxDoc = [[self.wordsCollection documentWithID: @"word4" error: &error] toMutable];
    CBLMutableArray* vector = [auxDoc arrayForKey: @"vector"];
    [vector removeValueAtIndex: 0];
    Assert([self.wordsCollection saveDocument: auxDoc error: &error]);
    
    // Create vector index
    [self createWordsIndexWithConfig: VECTOR_INDEX_CONFIG(@"vector", 300, 8)];
    
    // Query:
    CBLQueryResultSet* rs = [self executeWordsQueryWithLimit: 350];
    NSDictionary<NSString*, NSString*>* wordMap = [self toDocIDWordMap: rs];
    AssertEqual(wordMap.count, 296);
    AssertNil(wordMap[@"word1"]);
    AssertNil(wordMap[@"word2"]);
    AssertNil(wordMap[@"word3"]);
    AssertNil(wordMap[@"word4"]);
    Assert([self checkIndexWasTrained]);
    
    // Update doc:
    auxDoc = [[self.wordsCollection documentWithID: @"word5" error: &error] toMutable];
    [auxDoc setString: nil forKey: @"vector"];
    [self.wordsCollection saveDocument: auxDoc error: &error];
    
    // Query:
    rs = [self executeWordsQueryWithLimit: 350];
    wordMap = [self toDocIDWordMap: rs];
    AssertEqual(wordMap.count, 295);
    AssertNil(wordMap[@"word5"]);
}

/**
 * 8. TestCreateVectorIndexUsingPredictionModel
 * Description
 *     Using the default configuration, test that the vector index can be created from
 *     the vectors returned by a predictive model.
 * Steps
 *     1. Copy database words_db.
 *     2. Register a custom logger to capture the INFO log.
 *     3. Register  "WordEmbedding" predictive model defined in section 2.
 *     4. Create a vector index named "words_pred_index" in _default.words collection.
 *         - expression: "prediction(WordEmbedding, {"word": word}).vector"
 *         - dimensions: 300
 *         - centroids: 8
 *     5. Check that the index is created without an error returned.
 *     6. Create an SQL++ query:
 *         - SELECT meta().id, word
 *           FROM _default.words
 *           ORDER BY APPROX_VECTOR_DISTANCE(prediction(WordEmbedding, {'word': word}).vector, $dinerVector)
 *           LIMIT 350
 *     7. Check the explain() result of the query to ensure that the "words_pred_index" is used.
 *     8. Execute the query and check that 300 results are returned.
 *     9. Verify that the index was trained by checking that the “Untrained index; queries may be slow”
 *       doesn’t exist in the log.
 *     10. Update the vector index:
 *         - Create _default.words.word301 with the content from _default.extwords.word1
 *         - Create _default.words.word302 with the content from _default.extwords.word2
 *         - Update _default.words.word1 with the content from _default.extwords.word3
 *         - Delete _default.words.word2
 *     11. Execute the query and check that 301 results are returned.
 *         - word301 and word302 are included.
 *         - word1 is updated with the word from _default.extwords.word2.
 *         - word2 is not included.
 *     12. Reset the custom logger.
 */
- (void) testCreateVectorIndexUsingPredictionModel {
    [self registerPredictiveModel];
    
    NSString* expr = @"prediction(WordEmbedding,{\"word\": word}).vector";
    [self createWordsIndexWithConfig: VECTOR_INDEX_CONFIG(expr, 300, 8)];
    
    CBLQueryResultSet* rs = [self executeWordsQueryWithLimit: 350
                                                      metric: nil
                                            vectorExpression: expr
                                                 whereClause: nil
                                               checkTraining: true];
    AssertEqual(rs.allObjects.count, 300);
    
    // Create words.word301 with extwords.word1 content
    NSError* error;
    CBLDocument* extWord1 = [self.extWordsCollection documentWithID: @"word1" error : &error];
    CBLMutableDocument* word301 = [self createDocument: @"word301" data: [extWord1 toDictionary]];
    Assert([self.wordsCollection saveDocument: word301 error: &error]);
    
    // Create words.word302 with extwords.word2 content
    CBLDocument* extWord2 = [self.extWordsCollection documentWithID: @"word2" error : &error];
    CBLMutableDocument* word302 = [self createDocument: @"word302" data: [extWord2 toDictionary]];
    Assert([self.wordsCollection saveDocument: word302 error: &error]);
    
    // Update words.word1 with extwords.word3 content
    CBLDocument* extWord3 = [self.extWordsCollection documentWithID: @"word3" error : &error];
    CBLMutableDocument* word1 = [[self.wordsCollection documentWithID: @"word1" error: &error] toMutable];
    [word1 setData: [extWord3 toDictionary]];
    Assert([self.wordsCollection saveDocument: word1 error: &error]);
    
    // Delete words.word2
    [self.wordsCollection deleteDocument: [self.wordsCollection documentWithID: @"word2" error : &error]
                                   error: &error];
    
    rs = [self executeWordsQueryWithLimit: 350
                                   metric: nil
                         vectorExpression: expr
                              whereClause: nil
                            checkTraining: true];
    NSDictionary<NSString*, NSString*>* wordMap = [self toDocIDWordMap: rs];
    AssertEqual(wordMap.count, 301);
    AssertEqualObjects(wordMap[@"word301"], [word301 stringForKey: @"word"]);
    AssertEqualObjects(wordMap[@"word302"], [word302 stringForKey: @"word"]);
    AssertEqualObjects(wordMap[@"word1"], [word1 stringForKey: @"word"]);
    AssertNil(wordMap[@"word2"]);
}

/**
 * 9. TestCreateVectorIndexUsingPredictiveModelWithInvalidVectors
 * Description
 *     Using the default configuration, test that when creating the vector index using
 *     a predictive model with invalid vectors, the invalid vectors will be skipped
 *     from indexing.
 * Steps
 *     1. Copy database words_db.
 *     2. Register a custom logger to capture the INFO log.
 *     3. Register  "WordEmbedding" predictive model defined in section 2.
 *     4. Update documents.
 *         - Update _default.words word1 with "vector" = null
 *         - Update _default.words word2 with "vector" = "string"
 *         - Update _default.words word3 by removing the "vector" key.
 *         - Update _default.words word4 by removing one number from the "vector" key.
 *     5. Create a vector index named "words_prediction_index" in _default.words collection.
 *         - expression: "prediction(WordEmbedding, {"word": word}).embedding"
 *         - dimensions: 300
 *         - centroids: 8
 *     6. Check that the index is created without an error returned.
 *     7. Create an SQL++ query.
 *         - SELECT meta().id, word
 *           FROM _default.words
 *           ORDER BY APPROX_VECTOR_DISTANCE(prediction(WordEmbedding, {'word': word}).vector, $dinerVector)
 *           LIMIT 350
 *     8. Check the explain() result of the query to ensure that the "words_predi_index" is used.
 *     9. Execute the query and check that 296 results are returned and the results
 *        do not include word1, word2, word3, and word4.
 *     10. Verify that the index was trained by checking that the “Untrained index; queries may be slow” doesn’t exist in the log.
 *     11. Update an already index vector with a non existing word in the database.
 *         - Update _default.words.word5 with “word” = “Fried Chicken”.
 *     12. Execute the query and check that 295 results are returned, and the results
 *         do not include document word5.
 *     13. Reset the custom logger.
 */
- (void) testCreateVectorIndexUsingPredictionModelWithInvalidVectors {
    [self registerPredictiveModel];
    
    // Update docs:
    NSError* error;
    CBLMutableDocument* auxDoc = [[self.wordsCollection documentWithID: @"word1" error: &error] toMutable];
    [auxDoc setArray: nil forKey: @"vector"];
    Assert([self.wordsCollection saveDocument: auxDoc error: &error]);
    
    auxDoc = [[self.wordsCollection documentWithID: @"word2" error: &error] toMutable];
    [auxDoc setString: @"string" forKey: @"vector"];
    Assert([self.wordsCollection saveDocument:auxDoc error:&error]);
    
    auxDoc = [[self.wordsCollection documentWithID: @"word3" error: &error] toMutable];
    [auxDoc removeValueForKey: @"vector"];
    Assert([self.wordsCollection saveDocument:auxDoc error:&error]);

    auxDoc = [[self.wordsCollection documentWithID: @"word4" error: &error] toMutable];
    CBLMutableArray* vector = [auxDoc arrayForKey: @"vector"];
    [vector removeValueAtIndex: 0];
    Assert([self.wordsCollection saveDocument: auxDoc error: &error]);

    // Create vector index
    NSString* expr = @"prediction(WordEmbedding,{\"word\": word}).vector";
    [self createWordsIndexWithConfig: VECTOR_INDEX_CONFIG(expr, 300, 8)];
    
    // Query:
    CBLQueryResultSet* rs = [self executeWordsQueryWithLimit: 350
                                                      metric: nil
                                            vectorExpression: expr
                                                 whereClause: nil
                                               checkTraining: true];
    NSDictionary<NSString*, NSString*>* wordMap = [self toDocIDWordMap: rs];
    AssertEqual(wordMap.count, 296);
    AssertNil(wordMap[@"word1"]);
    AssertNil(wordMap[@"word2"]);
    AssertNil(wordMap[@"word3"]);
    AssertNil(wordMap[@"word4"]);
    Assert([self checkIndexWasTrained]);
    
    auxDoc = [[self.wordsCollection documentWithID: @"word5" error: &error] toMutable];
    [auxDoc setString: @"Fried Chicken" forKey: @"word"];
    Assert([self.wordsCollection saveDocument: auxDoc error: &error]);

    rs = [self executeWordsQueryWithLimit: 350
                                   metric: nil
                         vectorExpression: expr
                              whereClause: nil
                            checkTraining: true];
    wordMap = [self toDocIDWordMap: rs];
    AssertEqual(wordMap.count, 295);
    AssertNil(wordMap[@"word5"]);
}

/**
 * 10. TestCreateVectorIndexWithSQ
 * Description
 *     Using different types of the Scalar Quantizer Encoding, test that the vector
 *     index can be created and used.
 * Steps
 *     1. Copy database words_db.
 *     2. Register a custom logger to capture the INFO log.
 *     3. Create a vector index named "words_index" in _default.words collection.
 *         - expression: "vector"
 *         - dimensions: 300
 *         - centroids: 8
 *         - encoding: ScalarQuantizer(type: SQ4)
 *     4. Check that the index is created without an error returned.
 *     5. Create an SQL++ query
 *         - SELECT meta().id, word
 *           FROM _default.words
 *           ORDER BY APPROX_VECTOR_DISTANCE(vector, $dinerVector)
 *           LIMIT 20
 *     6. Check the explain() result of the query to ensure that the "words_index" is used.
 *     7. Execute the query and check that 20 results are returned.
 *     8. Verify that the index was trained by checking that the “Untrained index; queries may be slow” 
 *       doesn’t exist in the log.
 *     9. Delete the "words_index".
 *     10. Reset the custom logger.
 *     11. Repeat Step 2 – 10 by using SQ6 and SQ8 respectively.
 */
- (void) testCreateVectorIndexWithSQ {
    // Create vector index
    CBLVectorIndexConfiguration* config = VECTOR_INDEX_CONFIG(@"vector", 300, 8);
    config.encoding = [CBLVectorEncoding scalarQuantizerWithType: kCBLSQ4];
    [self createWordsIndexWithConfig: config];
    
    CBLQueryResultSet* rs = [self executeWordsQueryWithLimit: 20];
    AssertEqual(rs.allObjects.count, 20);
    
    // Repeat using SQ6
    [self resetIndexWasTrainedLog];
    [self deleteWordsIndex];
    config.encoding = [CBLVectorEncoding scalarQuantizerWithType: kCBLSQ6];
    [self createWordsIndexWithConfig: config];
    
    // Rerun query:
    rs = [self executeWordsQueryWithLimit: 20];
    AssertEqual(rs.allObjects.count, 20);
    
    // Repeat using SQ8
    [self resetIndexWasTrainedLog];
    [self deleteWordsIndex];
    config.encoding = [CBLVectorEncoding scalarQuantizerWithType: kCBLSQ8];
    [self createWordsIndexWithConfig: config];
    
    // Rerun query:
    rs = [self executeWordsQueryWithLimit: 20];
    AssertEqual(rs.allObjects.count, 20);
}

/**
 * 11. TestCreateVectorIndexWithNoneEncoding
 * Description
 *     Using the None Encoding, test that the vector index can be created and used.
 * Steps
 *     1. Copy database words_db.
 *     2. Register a custom logger to capture the INFO log.
 *     3. Create a vector index named "words_index" in _default.words collection.
 *         - expression: "vector"
 *         - dimensions: 300
 *         - centroids: 8
 *         - encoding: None
 *     4. Check that the index is created without an error returned.
 *     5. Create an SQL++ query.
 *         - SELECT meta().id, word
 *           FROM _default.words
 *           ORDER BY APPROX_VECTOR_DISTANCE(vector, $dinerVector)
 *           LIMIT 20
 *     6. Check the explain() result of the query to ensure that the "words_index" is used.
 *     7. Execute the query and check that 20 results are returned.
 *     8. Verify that the index was trained by checking that the “Untrained index; queries may be slow”
 *       doesn’t exist in the log.
 *     9. Reset the custom logger.
 */
- (void) testCreateVectorIndexWithNoneEncoding {
    CBLVectorIndexConfiguration* config = VECTOR_INDEX_CONFIG(@"vector", 300, 8);
    config.encoding = [CBLVectorEncoding none];
    [self createWordsIndexWithConfig: config];
    
    CBLQueryResultSet* rs = [self executeWordsQueryWithLimit: 20];
    AssertEqual(rs.allObjects.count, 20);
}

/**
 * 12. TestCreateVectorIndexWithPQ
 * Description
 *     Using the PQ Encoding, test that the vector index can be created and used. The
 *     test also tests the lower and upper bounds of the PQ’s bits.
 * Steps
 *     1. Copy database words_db.
 *     2. Register a custom logger to capture the INFO log.
 *     3. Create a vector index named "words_index" in _default.words collection.
 *         - expression: "vector"
 *         - dimensions: 300
 *         - centroids: 8
 *         - encoding : PQ(subquantizers: 5 bits: 8)
 *     4. Check that the index is created without an error returned.
 *     5. Create an SQL++ query.
 *         - SELECT meta().id, word
 *           FROM _default.words
 *           ORDER BY APPROX_VECTOR_DISTANCE(vector, $dinerVector)
 *           LIMIT 20
 *     6. Check the explain() result of the query to ensure that the "words_index" is used.
 *     7. Execute the query and check that 20 results are returned.
 *     8. Verify that the index was trained by checking that the “Untrained index; queries may be slow”
 *       doesn’t exist in the log.
 *     9. Delete the “words_index”.
 *     10. Reset the custom logger.
 *     11. Repeat steps 2 to 10 by changing the PQ’s bits to 4 and 12 respectively.
 */
- (void) testCreateVectorIndexWithPQ {
    for (NSNumber* bits in @[@4, @8, @12]) {
        // Create vector index
        CBLVectorIndexConfiguration* config = VECTOR_INDEX_CONFIG(@"vector", 300, 8);
        config.encoding = [CBLVectorEncoding productQuantizerWithSubquantizers: 5 bits: bits.unsignedIntValue];
        [self createWordsIndexWithConfig: config];
        
        // Query:
        CBLQueryResultSet* rs = [self executeWordsQueryNoTrainingCheckWithLimit: 20];
        AssertEqual(rs.allObjects.count, 20);
        
        // Delete index
        Assert([self.wordsCollection deleteIndexWithName: @"words_index" error: nil]);
    }
}

/**
 * 13. TestSubquantizersValidation
 * Description
 *     Test that the PQ’s subquantizers value is validated with dimensions correctly.
 *     The invalid argument exception should be thrown when the vector index is created
 *     with invalid subquantizers which are not a divisor of the dimensions or zero.
 * Steps
 *     1. Copy database words_db.
 *     2. Create a vector index named "words_index" in _default.words collection.
 *         - expression: "vector"
 *         - dimensions: 300
 *         - centroids: 8
 *         - PQ(subquantizers: 2, bits: 8)
 *     3. Check that the index is created without an error returned.
 *     4. Delete the "words_index".
 *     5. Repeat steps 2 to 4 by changing the subquantizers to
 *       3, 4, 5, 6, 10, 12, 15, 20, 25, 30, 50, 60, 75, 100, 150, and 300.
 *     6. Repeat step 2 to 4 by changing the subquantizers to 0 and 7.
 *     7. Check that an invalid argument exception is thrown.
 */
- (void) testSubquantizersValidation {
    CBLVectorIndexConfiguration* config = VECTOR_INDEX_CONFIG(@"vector", 300, 8);
    
    // Step 5: Use valid subquantizer values
    for (NSNumber* subq in @[@3, @4, @5, @150, @300]) {
        config.encoding = [CBLVectorEncoding productQuantizerWithSubquantizers: subq.unsignedIntValue bits: 8];
        [self createWordsIndexWithConfig: config];
        [self deleteWordsIndex];
    }
    
    // Step 7: Check if exception thrown for wrong subquantizers:
    CBLCollection* collection = self.wordsCollection;
    for (NSNumber* subq in @[@0, @7]) {
        config.encoding = [CBLVectorEncoding productQuantizerWithSubquantizers: subq.unsignedIntValue bits: 8];
        [self expectException: NSInvalidArgumentException in: ^{
            [collection createIndexWithName: kWordsIndexName config: config error: nil];
        }];
        [self deleteWordsIndex];
    }
}

/**
 * 14. TestCreateVectorIndexWithFixedTrainingSize
 * Description
 *     Test that the vector index can be created and trained when minTrainingSize
 *     equals to maxTrainingSize.
 * Steps
 *     1. Copy database words_db.
 *     2. Register a custom logger to capture the INFO log.
 *     3. Create a vector index named "words_index" in _default.words collection.
 *         - expression: "vector"
 *         - dimensions: 300
 *         - centroids: 8
 *         - minTrainingSize: 100 and maxTrainingSize: 100
 *     4. Check that the index is created without an error returned.
 *     5. Create an SQL++ query.
 *         - SELECT meta().id, word
 *           FROM _default.words
 *           ORDER BY APPROX_VECTOR_DISTANCE(vector, $dinerVector)
 *           LIMIT 20
 *     5. Check the explain() result of the query to ensure that the "words_index" is used.
 *     6. Execute the query and check that 20 results are returned.
 *     7. Verify that the index was trained by checking that the “Untrained index; queries may be slow”
 *       doesn’t exist in the log.
 *     8. Reset the custom logger.
 */
- (void) testeCreateVectorIndexWithFixedTrainingSize {
    CBLVectorIndexConfiguration* config = VECTOR_INDEX_CONFIG(@"vector", 300, 8);
    config.minTrainingSize = 100;
    config.maxTrainingSize = 100;
    [self createWordsIndexWithConfig: config];
    
    CBLQueryResultSet* rs = [self executeWordsQueryWithLimit: 20];
    AssertEqual(rs.allObjects.count, 20);
}

/**
 * 15. TestValidateMinMaxTrainingSize
 * Description
 *     Test that the minTrainingSize and maxTrainingSize values are validated
 *     correctly. The invalid argument exception should be thrown when the vector index
 *     is created with invalid minTrainingSize or maxTrainingSize.
 * Steps
 *     1. Copy database words_db.
 *     2. Create a vector index named "words_index" in _default.words collection.
 *         - expression: "vector"
 *         - dimensions: 300
 *         - centroids: 8
 *         - minTrainingSize: 1 and maxTrainingSize: 100
 *     3. Check that the index is created without an error returned.
 *     4. Delete the "words_index"
 *     5. Repeat Step 2 with the following case:
 *         - minTrainingSize = 10 and maxTrainingSize = 9
 *     6. Check that an invalid argument exception was thrown.
 */
- (void) testValidateMinMaxTrainingSize {
    CBLVectorIndexConfiguration* config = VECTOR_INDEX_CONFIG(@"vector", 300, 8);
    config.minTrainingSize = 1;
    config.maxTrainingSize = 100;
    [self createWordsIndexWithConfig: config];
    
    [self deleteWordsIndex];
    config.minTrainingSize = 10;
    config.maxTrainingSize = 9;
    CBLCollection* collection = self.wordsCollection;
    [self expectException: NSInvalidArgumentException in:^{
        [collection createIndexWithName: kWordsIndexName config: config error: nil];
    }];
}

/**
 * 16. TestQueryUntrainedVectorIndex
 * Description
 *     Test that the untrained vector index can be used in queries.
 * Steps
 *     1. Copy database words_db.
 *     2. Register a custom logger to capture the INFO log.
 *     3. Create a vector index named "words_index" in _default.words collection.
 *         - expression: "vector"
 *         - dimensions: 300
 *         - centroids: 8
 *         - minTrainingSize: 400
 *         - maxTrainingSize: 500
 *     4. Check that the index is created without an error returned.
 *     5. Create an SQL++ query.
 *         - SELECT meta().id, word
 *           FROM _default.words
 *           ORDER BY APPROX_VECTOR_DISTANCE(vector, $dinerVector)
 *           LIMIT 20
 *     6. Check the explain() result of the query to ensure that the "words_index" is used.
 *     7. Execute the query and check that 20 results are returned.
 *     8. Verify that the index was not trained by checking that the “Untrained index;
 *       queries may be slow” message exists in the log.
 *     9. Reset the custom logger.
 */
- (void) testQueryUntrainedVectorIndex {
    CBLVectorIndexConfiguration* config = VECTOR_INDEX_CONFIG(@"vector", 300, 8);
    config.minTrainingSize = 400;
    config.maxTrainingSize = 500;
    [self createWordsIndexWithConfig: config];
    
    CBLQueryResultSet* rs = [self executeWordsQueryNoTrainingCheckWithLimit: 20];
    AssertEqual(rs.allObjects.count, 20);
    AssertFalse([self checkIndexWasTrained]);
}

/**
 * 17. TestCreateVectorIndexWithDistanceMetric
 * Description
 *     Test that the vector index can be created with all supported distance metrics.
 * Steps
 *     1. Copy database words_db.
 *     2. For each distance metric types : euclideanSquared, euclidean, cosine, and dot,
 *       create a vector index named "words_index" in _default.words collection:
 *        - expression: "vector"
 *        - dimensions: 300
 *        - centroids : 8
 *        - metric: <distance-metric>
 *     3. Check that the index is created without an error returned.
 *     4. Create an SQL++ query with the correspoding SQL++ metric name string:
 *       "EUCLIDEAN_SQUARED", "EUCLIDEAN", "COSINE", and "DOT"
 *        - SELECT meta().id, word
 *          FROM _default.words
 *          ORDER BY APPROX_VECTOR_DISTANCE(vector, $dinerVector, "<metric-name>")
 *          LIMIT 20
 *     5. Check the explain() result of the query to ensure that the "words_index" is used.
 *     6. Execute the query and check that 20 results are returned.
 *     7. Verify that the index was trained.
 */
- (void) testCreateVectorIndexWithDistanceMetric {
    NSArray<NSNumber*>*metrics = @[
        @(kCBLDistanceMetricEuclideanSquared),
        @(kCBLDistanceMetricEuclidean),
        @(kCBLDistanceMetricCosine),
        @(kCBLDistanceMetricDot)
    ];
    
    NSArray<NSString*>*metricNames = @[
        @"EUCLIDEAN_SQUARED",
        @"EUCLIDEAN",
        @"COSINE",
        @"DOT"
    ];
    
    for (NSUInteger i = 0; i < metrics.count; i++) {
        CBLDistanceMetric metic = (CBLDistanceMetric)[metrics[i] intValue];
        NSString* metricName = metricNames[i];
        
        CBLVectorIndexConfiguration* config = VECTOR_INDEX_CONFIG(@"vector", 300, 8);
        config.metric = metic;
        [self createWordsIndexWithConfig: config];
    
        CBLQueryResultSet* rs = [self executeWordsQueryWithLimit: 20
                                                          metric: metricName
                                                vectorExpression: @"vector"
                                                     whereClause: nil
                                                   checkTraining: true];
        NSArray* results = rs.allResults;
        AssertEqual(results.count, 20);
    }
}

/**
 * 19. TestCreateVectorIndexWithExistingName
 * Description
 *     Test that creating a new vector index with an existing name is fine if the index
 *     configuration is the same or not.
 * Steps
 *     1. Copy database words_db.
 *     2. Create a vector index named "words_index" in _default.words collection.
 *         - expression: "vector"
 *         - dimensions: 300
 *         - centroids: 20
 *     3. Check that the index is created without an error returned.
 *     4. Repeat step 2 and check that the index is created without an error returned.
 *     5. Create a vector index named "words_index" in _default.words collection.
 *         - expression: "vectors"
 *         - dimensions: 300
 *         - centroids: 20
 *     6. Check that the index is created without an error returned.
 */
- (void) testCreateVectorIndexWithExistingName {
    CBLVectorIndexConfiguration* config = VECTOR_INDEX_CONFIG(@"vector", 300, 8);
    [self createWordsIndexWithConfig: config];
    [self createWordsIndexWithConfig: config];
    
    config = VECTOR_INDEX_CONFIG(@"vectors", 300, 8);
    [self createWordsIndexWithConfig: config];
}

/**
 * 20. TestDeleteVectorIndex
 * Description
 *     Test that creating a new vector index with an existing name is fine if the index
 *     configuration is the same. Otherwise, an error will be returned.
 * Steps
 *     1. Copy database words_db.
 *     2. Register a custom logger to capture the INFO log.
 *     3. Create a vector index named "words_index" in _default.words collection.
 *         - expression: "vectors"
 *         - dimensions: 300
 *         - centroids: 8
 *     4. Check that the index is created without an error returned.
 *     5. Create an SQL++ query.
 *         - SELECT meta().id, word
 *           FROM _default.words
 *           ORDER BY APPROX_VECTOR_DISTANCE(vector, $dinerVector)
 *           LIMIT 20
 *     6. Check the explain() result of the query to ensure that the "words_index" is used.
 *     7. Execute the query and check that 20 results are returned.
 *     8. Verify that the index was trained by checking that the “Untrained index; queries may be slow”
 *       doesn’t exist in the log.
 *     9. Delete index named "words_index".
 *     10. Check that getIndexes() does not contain "words_index".
 *     11. Create the same query again and check that a CouchbaseLiteException is returned
 *        as the index doesn’t exist.
 *     12. Reset the custom logger.
 */
- (void) testDeleteVectorIndex {
    CBLVectorIndexConfiguration* config = VECTOR_INDEX_CONFIG(@"vector", 300, 8);
    [self createWordsIndexWithConfig: config];
    
    CBLQueryResultSet* rs = [self executeWordsQueryWithLimit: 20];
    AssertEqual(rs.allObjects.count, 20);
    
    [self deleteWordsIndex];
    
    [self expectError: CBLErrorDomain code: CBLErrorMissingIndex in: ^BOOL(NSError **err) {
        NSString* sql = [self wordsQueryStringWithLimit: 20 metric: nil vectorExpression: nil whereClause: nil];
        return [self.wordDB createQuery: sql error: err] != nil;
    }];
}

/**
 * 21. TestVectorMatchOnNonExistingIndex
 * Description
 *     Test that an error will be returned when creating a vector match query that uses
 *     a non existing index.
 * Steps
 *     1. Copy database words_db.
 *     2. Create an SQL++ query.
 *         - SELECT meta().id, word
 *           FROM _default.words
 *           ORDER BY APPROX_VECTOR_DISTANCE(vector, $dinerVector)
 *           LIMIT 20
 *     3. Check that a CouchbaseLiteException is returned as the index doesn’t exist.
 */
- (void) testVectorMatchOnNonExistingIndex {
    [self expectError: CBLErrorDomain code: CBLErrorMissingIndex in: ^BOOL(NSError **err) {
        NSString* sql = [self wordsQueryStringWithLimit: 20 metric: nil vectorExpression: nil whereClause: nil];
        return [self.wordDB createQuery: sql error: err] != nil;
    }];
}

/**
 * 23. TestVectorMatchLimitBoundary
 * Description
 *     Test vector_match’s limit boundary which is between 1 - 10000 inclusively. When
 *     creating vector_match queries with an out-out-bound limit, an error should be
 *     returned.
 * Steps
 *     1. Copy database words_db.
 *     2. Create a vector index named "words_index" in _default.words collection.
 *         - expression: "vector"
 *         - dimensions: 300
 *         - centroids: 8
 *     3. Check that the index is created without an error returned.
 *     4. Create an SQL++ query.
 *         - SELECT meta().id, word
 *           FROM _default.words
 *           ORDER BY APPROX_VECTOR_DISTANCE(vector, $dinerVector)
 *           LIMIT <limit>
 *         - limit: 1 and 10000
 *     5. Check that the query can be created without an error.
 *     6. Repeat step 4 with the limit: -1, 0, and 10001
 *     7. Check that a CouchbaseLiteException is returned when creating the query.
 */
- (void) testVectorMatchLimitBoundary {
    CBLVectorIndexConfiguration* config = VECTOR_INDEX_CONFIG(@"vector", 300, 8);
    [self createWordsIndexWithConfig: config];
    
    // Check valid query with -1, 0, 1 and 10000 set limit
    for (NSNumber* limit in @[@-1, @0, @1, @10000]) {
        NSError* error;
        NSString* sql = [self wordsQueryStringWithLimit: [limit integerValue]];
        Assert([self.wordDB createQuery: sql error: &error]);
        AssertNil(error);
    }
    
    // Check if error thrown for wrong limit values
    [self expectError: CBLErrorDomain code: CBLErrorInvalidQuery in: ^BOOL(NSError** err) {
        NSString* sql = [self wordsQueryStringWithLimit: 10001];
        return [self.wordDB createQuery: sql error: err] != nil;
    }];
}

/**
 * 24. TestHybridVectorSearch
 * Description
 *     Test a simple hybrid search with WHERE clause.
 * Steps
 *     1. Copy database words_db.
 *     2. Register a custom logger to capture the INFO log.
 *     3. Create a vector index named "words_index" in _default.words collection.
 *         - expression: "vector"
 *         - dimensions: 300
 *         - centroids: 8
 *     4. Check that the index is created without an error returned.
 *     5. Create an SQL++ query.
 *         - SELECT word, catid
 *           FROM _default.words
 *           WHERE catid = "cat1"
 *           ORDER BY APPROX_VECTOR_DISTANCE(vector, $dinerVector)
 *           LIMIT 300
 *     6. Check that the query can be created without an error.
 *     7. Check the explain() result of the query to ensure that the "words_index" is used.
 *     8. Execute the query and check that the number of results returned is 50
 *       (there are 50 words in catid=1), and the results contain only catid == 'cat1'.
 *     9. Verify that the index was trained by checking that the “Untrained index; queries may be slow”
 *       doesn’t exist in the log.
 *     10. Reset the custom logger.
 */
- (void) testHybridVectorSearch {
    CBLVectorIndexConfiguration* config = VECTOR_INDEX_CONFIG(@"vector", 300, 8);
    [self createWordsIndexWithConfig: config];
    
    CBLQueryResultSet* rs = [self executeWordsQueryWithLimit: 300
                                                      metric: nil
                                            vectorExpression: @"vector"
                                                 whereClause: @"catid = 'cat1'"
                                               checkTraining: true];
    
    NSArray* results = rs.allResults;
    AssertEqual(results.count, 50);
    for(CBLQueryResult* result in results){
        AssertEqualObjects([result valueAtIndex: 2], @"cat1");
    }
}

/**
 * 25. TestHybridVectorSearchWithAND
 * Description
 *     Test hybrid search with multiple AND
 * Steps
 *     1. Copy database words_db.
 *     2. Register a custom logger to capture the INFO log.
 *     3. Create a vector index named "words_index" in _default.words collection.
 *         - expression: "vector"
 *         - dimensions: 300
 *         - centroids: 8
 *     4. Check that the index is created without an error returned.
 *     5. Create an SQL++ query.
 *         - SELECT word, catid
 *           FROM _default.words
 *           WHERE catid = "cat1" AND word is valued
 *           ORDER BY APPROX_VECTOR_DISTANCE(vector, $dinerVector)
 *           LIMIT 300
 *     6. Check that the query can be created without an error.
 *     7. Check the explain() result of the query to ensure that the "words_index" is used.
 *     8. Execute the query and check that the number of results returned is 50
 *       (there are 50 words in catid=1), and the results contain only catid == 'cat1'.
 *     9. Verify that the index was trained by checking that the “Untrained index; queries may be slow”
 *       doesn’t exist in the log.
 *     10. Reset the custom logger.
 */
- (void) testHybridVectorSearchWithAND {
    CBLVectorIndexConfiguration* config = VECTOR_INDEX_CONFIG(@"vector", 300, 8);
    [self createWordsIndexWithConfig: config];
    
    CBLQueryResultSet* rs = [self executeWordsQueryWithLimit: 300
                                                      metric: nil
                                            vectorExpression: @"vector"
                                                 whereClause: @"word is valued AND catid = 'cat1'"
                                               checkTraining: true];
    
    NSArray* results = rs.allResults;
    AssertEqual(results.count, 50);
    for(CBLQueryResult* result in results){
        AssertEqualObjects([result valueAtIndex: 2], @"cat1");
    }
}

/**
 * 26. TestInvalidHybridVectorSearchWithOR
 * Description
 *     Test that APPROX_VECTOR_DISTANCE cannot be used with OR expression.
 * Steps
 *     1. Copy database words_db.
 *     2. Create a vector index named "words_index" in _default.words collection.
 *         - expression: "vector"
 *         - dimensions: 300
 *         - centroids: 20
 *     3. Check that the index is created without an error returned.
 *     4. Create an SQL++ query.
 *         - SELECT word, catid
 *           FROM _default.words
 *           WHERE APPROX_VECTOR_DISTANCE(vector, $dinerVector) < 0.5 OR catid = 'cat1'
 *           ORDER BY APPROX_VECTOR_DISTANCE(vector, $dinerVector)
 *           LIMIT 20
 *     5. Check that a CouchbaseLiteException is returned when creating the query.
 */
- (void) testInvalidHybridVectorSearchWithOR {
    CBLVectorIndexConfiguration* config = VECTOR_INDEX_CONFIG(@"vector", 300, 8);
    [self createWordsIndexWithConfig: config];
    
    [self expectError: CBLErrorDomain code: CBLErrorInvalidQuery in: ^BOOL(NSError **err) {
        NSString* sql = [self wordsQueryStringWithLimit: 20
                                                 metric: nil
                                       vectorExpression: @"vector"
                                            whereClause: @"APPROX_VECTOR_DISTANCE(vector, $vector) < 0.5 OR catid = 'cat1'"];
        return [self.wordDB createQuery: sql error: err] != nil;
    }];
}

/**
 * 27. TestIndexVectorInBase64
 *
 * Description
 *      Test that the vector in Base64 string can be indexed.
 *
 * Steps
 *      1. Copy database words_db.
 *      2. Get the vector value from _default.words.word49's vector property as an array of floats.
 *      3. Convert the array of floats from Step 2 into binary data and then into Base64 string.
 *          - See "Vector in Base64 for Lunch" section for the pre-calculated base64 string
 *      4. Update _default.words.word49 with "vector" = Base64 string from Step 3.
 *      5. Create a vector index named "words_index" in _default.words collection.
 *          - expression: "vector"
 *          - dimensions: 300
 *          - centroids : 8
 *      6. Check that the index is created without an error returned.
 *      7. Create an SQL++ query:
 *          - SELECT meta().id, word,
 *            FROM _default.words
 *            WHERE vector_match(words_index, <dinner vector>)
 *            LIMIT 20
 *      8. Execute the query and check that 20 results are returned.
 *      9. Check that the result also contains doc id = word49.
 */
- (void) testIndexVectorInBase64 {
    NSError* error;
    CBLMutableDocument* doc = [[self.wordsCollection documentWithID: @"word49" error: &error] toMutable];
    [doc setString: kLunchVectorBase64 forKey: @"vector"];
    Assert([self.wordsCollection saveDocument: doc error: &error]);
    
    CBLVectorIndexConfiguration* config = VECTOR_INDEX_CONFIG(@"vector", 300, 8);
    [self createWordsIndexWithConfig: config];
    
    CBLQueryResultSet* rs = [self executeWordsQueryWithLimit: 20];
    NSDictionary<NSString*, NSString*>* wordMap = [self toDocIDWordMap: rs];
    AssertEqual(wordMap.count, 20);
    AssertNotNil(wordMap[@"word49"]);
}

/** 
 * 28. TestNumProbes
 *
 * Description
 *      Test that the numProces specified is effective.
 * Steps
 *      1. Copy database words_db.
 *      2. Create a vector index named "words_index" in _default.words collection.
 *          - expression: "vector"
 *          - dimensions: 300
 *          - centroids : 8
 *          - numProbes: 5
 *      3. Check that the index is created without an error returned.
 *      4. Create an SQL++ query:
 *          - SELECT meta().id, word
 *            FROM _default.words
 *            ORDER BY APPROX_VECTOR_DISTANCE(vector, $dinerVector)
 *            LIMIT 300
 *      5. Execute the query and check that 20 results are returned.
 *      6. Repeat step 2 - 6 but change the numProbes to 1.
 *      7. Verify the number of results returned in Step 5 is larger than Step 6.
*/
- (void) testNumProbes {
    CBLVectorIndexConfiguration* config = VECTOR_INDEX_CONFIG(@"vector", 300, 8);
    config.numProbes = 5;
    [self createWordsIndexWithConfig: config];
    
    CBLQueryResultSet* rs = [self executeWordsQueryWithLimit: 300];
    NSUInteger numResultsFor5Probes = [[rs allObjects] count];
    Assert(numResultsFor5Probes > 0);
    
    config.numProbes = 1;
    [self createWordsIndexWithConfig: config];
    rs = [self executeWordsQueryWithLimit: 300];
    NSUInteger numResultsFor1Probes = [[rs allObjects] count];
    Assert(numResultsFor1Probes > 0);
    
    Assert(numResultsFor5Probes > numResultsFor1Probes);
}

/*
 Private methods tests
 */

- (void) testIsEqual {
    CBLVectorIndexConfiguration* config = [[CBLVectorIndexConfiguration alloc] initWithExpression: @"vector"
                                                                                       dimensions: 300
                                                                                        centroids: 20];
    Assert([config.encoding isEqual: [CBLVectorEncoding scalarQuantizerWithType: kCBLSQ8]]);
}

- (void) testHash {
    CBLVectorIndexConfiguration* config = [[CBLVectorIndexConfiguration alloc] initWithExpression: @"vector"
                                                                                       dimensions: 300
                                                                                        centroids: 20];
    /* 
     type = 3 (SQ)
     bits = 8
    */
    AssertEqual(config.encoding.hash, 32682);
    
    config.encoding = [CBLVectorEncoding productQuantizerWithSubquantizers: 5 bits: 4];
    /*
     type = 2 (PQ)
     pq_subquantizers = 5
     bits = 4
    */
    AssertEqual(config.encoding.hash, 31872);
}

#endif

@end
