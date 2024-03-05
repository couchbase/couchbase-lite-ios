//
//  VectorIndexTest.m
//  CouchbaseLite
//
//  Copyright (c) 2024 Couchbase, Inc. All rights reserved.
//  COUCHBASE CONFIDENTIAL -- part of Couchbase Lite Enterprise Edition
//

#import "CBLErrors.h"
#import "CBLTestCase.h"
#import "CBLVectorEncoding.h"
#import "CBLWordEmbeddingModel.h"

#define kDinnerVector @[@0.03193166106939316, @0.032055653631687164, @0.07188114523887634, @(-0.09893740713596344), @(-0.07693558186292648), @0.07570040225982666, @0.42786234617233276, @(-0.11442682892084122), @(-0.7863243818283081), @(-0.47983086109161377), @(-0.10168658196926117), @0.10985997319221497, @(-0.15261511504650116), @(-0.08458329737186432), @(-0.16363860666751862), @(-0.20225222408771515), @(-0.2593214809894562), @(-0.032738097012043), @(-0.16649988293647766), @(-0.059701453894376755), @0.17472036182880402, @(-0.007310086861252785), @(-0.13918264210224152), @(-0.07260780036449432), @(-0.02461239881813526), @(-0.04195880889892578), @(-0.15714778006076813), @0.48038315773010254, @0.7536261677742004, @0.41809454560279846, @(-0.17144775390625), @0.18296195566654205, @(-0.10611499845981598), @0.11669538915157318, @0.07423929125070572, @(-0.3105475902557373), @(-0.045081984251737595), @(-0.18190748989582062), @0.22430984675884247, @0.05735112354159355, @(-0.017394868656992912), @(-0.148889422416687), @(-0.20618586242198944), @(-0.1446581482887268), @0.061972495168447495, @0.07787969708442688, @0.14225411415100098, @0.20560632646083832, @0.1786964386701584, @(-0.380594402551651), @(-0.18301603198051453), @(-0.19542981684207916), @0.3879885971546173, @(-0.2219538390636444), @0.11549852043390274, @(-0.0021717497147619724), @(-0.10556972026824951), @0.030264658853411674, @0.16252967715263367, @0.06010117009282112, @(-0.045007310807704926), @0.02435707487165928, @0.12623260915279388, @(-0.12688252329826355), @(-0.3306281864643097), @0.06452160328626633,@0.0707000121474266, @(-0.04959108680486679), @(-0.2567063570022583), @(-0.01878536120057106), @(-0.10857286304235458), @(-0.01754194125533104), @(-0.0713721290230751), @0.05946013703942299, @(-0.1821729987859726), @(-0.07293688505887985), @(-0.2778160572052002), @0.17880073189735413, @(-0.04669278487563133), @0.05351974070072174, @(-0.23292849957942963), @0.05746332183480263, @0.15462779998779297, @(-0.04772235080599785), @(-0.003306782804429531), @0.058290787041187286, @0.05908169597387314, @0.00504430802538991, @(-0.1262340396642685), @0.11612161248922348, @0.25303348898887634, @0.18580256402492523, @0.09704313427209854, @(-0.06087183952331543), @0.19697663187980652, @(-0.27528849244117737), @(-0.0837797075510025), @(-0.09988483041524887), @(-0.20565757155418396), @0.020984146744012833, @0.031014855951070786, @0.03521743416786194, @(-0.05171370506286621), @0.009112107567489147, @(-0.19296088814735413), @(-0.19363830983638763), @0.1591167151927948, @(-0.02629968523979187), @(-0.1695055067539215), @(-0.35807400941848755), @(-0.1935291737318039), @(-0.17090126872062683), @(-0.35123637318611145), @(-0.20035606622695923), @(-0.03487539291381836), @0.2650701701641083, @(-0.1588021069765091), @0.32268261909484863, @(-0.024521857500076294), @(-0.11985184997320175), @0.14826008677482605, @0.194917231798172, @0.07971998304128647, @0.07594677060842514, @0.007186363451182842, @(-0.14641280472278595), @0.053229596465826035, @0.0619836151599884, @0.003207010915502906, @(-0.12729716300964355), @0.13496214151382446, @0.107656329870224, @(-0.16516226530075073), @(-0.033881571143865585), @(-0.11175122112035751), @(-0.005806141998618841), @(-0.4765360355377197), @0.11495379358530045, @0.1472187340259552, @0.3781401813030243, @0.10045770555734634, @(-0.1352398842573166), @(-0.17544329166412354), @(-0.13191302120685577), @(-0.10440415143966675), @0.34598618745803833, @0.09728766977787018, @(-0.25583627820014954), @0.035236816853284836, @0.16205145418643951, @(-0.06128586828708649), @0.13735555112361908, @0.11582338809967041, @(-0.10182418674230576), @0.1370954066514969, @0.15048766136169434, @0.06671152263879776, @(-0.1884871870279312), @(-0.11004580557346344), @0.24694739282131195, @(-0.008159132674336433), @(-0.11668405681848526), @(-0.01214478351175785), @0.10379738360643387, @(-0.1626262664794922), @0.09377897530794144, @0.11594484746456146, @(-0.19621512293815613), @0.26271334290504456, @0.04888357222080231, @(-0.10103251039981842), @0.33250945806503296, @0.13565145432949066, @(-0.23888370394706726), @(-0.13335271179676056), @(-0.0076894499361515045), @0.18256276845932007, @0.3276212215423584, @(-0.06567271053791046), @(-0.1853761374950409), @0.08945729583501816, @0.13876311480998993, @0.09976287186145782, @0.07869105041027069, @(-0.1346970647573471), @0.29857659339904785, @0.1329529583454132, @0.11350086331367493, @0.09112624824047089, @(-0.12515446543693542), @(-0.07917925715446472), @0.2881546914577484, @(-1.4532661225530319e-05), @(-0.07712751626968384), @0.21063975989818573, @0.10858846455812454, @(-0.009552721865475178), @0.1629313975572586, @(-0.39703384041786194), @0.1904662847518921, @0.18924959003925323, @(-0.09611514210700989), @0.001136621693149209, @(-0.1293390840291977), @(-0.019481558352708817), @0.09661063551902771, @(-0.17659670114517212), @0.11671938002109528, @0.15038564801216125, @(-0.020016824826598167), @(-0.20642194151878357), @0.09050136059522629, @(-0.1768183410167694), @(-0.2891409397125244), @0.04596589505672455, @(-0.004407480824738741), @0.15323616564273834, @0.16503025591373444, @0.17370983958244324, @0.02883041836321354, @0.1463884711265564, @0.14786243438720703, @(-0.026439940556883812), @(-0.03113352134823799), @0.10978181660175323, @0.008928884752094746, @0.24813824892044067, @(-0.06918247044086456), @0.06958142668008804, @0.17475970089435577, @0.04911438003182411, @0.17614248394966125, @0.19236832857131958, @(-0.1425514668226242), @(-0.056531358510255814), @(-0.03680772706866264), @(-0.028677923604846), @(-0.11353116482496262), @0.012293893843889236, @(-0.05192646384239197), @0.20331953465938568, @0.09290937334299088, @0.15373043715953827, @0.21684466302394867, @0.40546831488609314, @(-0.23753701150417328), @0.27929359674453735, @(-0.07277711480855942), @0.046813879162073135, @0.06883064657449722, @(-0.1033223420381546), @0.15769273042678833, @0.21685580909252167, @(-0.00971329677850008), @0.17375953495502472, @0.027193285524845123, @(-0.09943609684705734), @0.05770351365208626, @0.0868956446647644, @(-0.02671697922050953), @(-0.02979189157485962), @0.024517420679330826, @(-0.03931192681193352), @(-0.35641804337501526), @(-0.10590721666812897), @(-0.2118944674730301), @(-0.22070199251174927), @0.0941486731171608, @0.19881175458431244, @0.1815279871225357, @(-0.1256905049085617), @(-0.0683583989739418), @0.19080783426761627, @(-0.009482398629188538), @(-0.04374842345714569), @0.08184348791837692, @0.20070189237594604, @0.039221834391355515, @(-0.12251003831624985), @(-0.04325549304485321), @0.03840530663728714, @(-0.19840988516807556), @(-0.13591833412647247), @0.03073180839419365, @0.1059495136141777, @(-0.10656466335058212), @0.048937033861875534, @(-0.1362423598766327), @(-0.04138947278261185), @0.10234509408473969, @0.09793911874294281, @0.1391254961490631, @(-0.0906999260187149), @0.146945983171463, @0.14941848814487457, @0.23930180072784424, @0.36049938201904297, @0.0239607822149992, @0.08884347230195999, @0.061145078390836716]

@interface VectorSearchTest : CBLTestCase

@end

@implementation VectorSearchTest

- (void) setUp {
    [super setUp];
}

- (void) tearDown {
    [super tearDown];
}

- (void) initDB {
    NSError* error;
    CBLDatabaseConfiguration* config = [[CBLDatabaseConfiguration alloc] init];
    config.directory = self.directory;
    
    NSString* path = [self databasePath: @"words_db.cblite2" inDirectory: @"vectorsearch"];
    [CBLDatabase copyFromPath:path toDatabase: kDatabaseName withConfig: config error: &error];
    
    [self openDB];
}

- (void) testVectorIndexConfigurationDefaultValue {
    CBLVectorIndexConfiguration* config = [[CBLVectorIndexConfiguration alloc] initWithExpression: @"vector"
                                                                                       dimensions: 300
                                                                                        centroids: 20];
    AssertEqualObjects(config.encoding, [CBLVectorEncoding scalarQuantizerWithType: kCBLSQ8]);
    AssertEqual(config.metric, kCBLDistanceMetricEuclidean);
    AssertEqual(config.minTrainingSize, 25 * config.centroids);
    AssertEqual(config.maxTrainingSize, 256 * config.centroids);
}


- (void) testVectorIndexConfigurationSettersAndGetters {
    CBLVectorIndexConfiguration* config = [[CBLVectorIndexConfiguration alloc] initWithExpression: @"vector"
                                                                                       dimensions: 300
                                                                                        centroids: 20];
    CBLVectorEncoding* noneEncoding = [CBLVectorEncoding none];
    config.encoding = noneEncoding;
    config.metric = kCBLDistanceMetricCosine;
    config.minTrainingSize = 100;
    config.maxTrainingSize = 200;
    
    AssertEqual(config.expression, @"vector");
    AssertEqualObjects(config.expressions, @[@"vector"]);
    AssertEqual(config.dimensions, 300);
    AssertEqual(config.centroids, 20);
    AssertEqual(config.encoding, noneEncoding);
    AssertEqual(config.metric, kCBLDistanceMetricCosine);
    AssertEqual(config.minTrainingSize, 100);
    AssertEqual(config.maxTrainingSize, 200);
}

// CBL-5462
- (void) _testDimensionsValidation {
    NSError* error;
    CBLCollection* collection = [_db collectionWithName: @"words" scope: nil error: &error];
    
    CBLVectorIndexConfiguration* config1 = [[CBLVectorIndexConfiguration alloc] initWithExpression: @"vector"
                                                                                        dimensions: 1
                                                                                         centroids: 20];
    AssertNotNil(config1);
    Assert([collection createIndexWithName: @"words_index_1" config: config1 error: &error]);
    NSArray* names = [collection indexes: &error];
    Assert([names containsObject: @"words_index_1"]);
    
    CBLVectorIndexConfiguration* config2 = [[CBLVectorIndexConfiguration alloc] initWithExpression: @"vector"
                                                                                        dimensions: 2048
                                                                                         centroids: 20];
    AssertNotNil(config2);
    Assert([collection createIndexWithName: @"words_index_2" config: config2 error: &error]);
    names = [collection indexes: &error];
    Assert([names containsObject: @"words_index_2"]);
    
    [self expectException: NSInvalidArgumentException in:^{
        (void) [[CBLVectorIndexConfiguration alloc] initWithExpression: @"vector"
                                                            dimensions: 0 
                                                             centroids: 20];
    }];
    
    [self expectException: NSInvalidArgumentException in:^{
        (void) [[CBLVectorIndexConfiguration alloc] initWithExpression: @"vector" 
                                                            dimensions: 2049 
                                                             centroids: 20];
    }];
}

// CBL-5463
- (void) _testCentroidsValidation {
    NSError* error;
    CBLCollection* collection = [_db collectionWithName: @"words" scope: nil error: &error];
    
    CBLVectorIndexConfiguration* config1 = [[CBLVectorIndexConfiguration alloc] initWithExpression: @"vector"
                                                                                        dimensions: 300
                                                                                         centroids: 1];
    AssertNotNil(config1);
    Assert([collection createIndexWithName: @"words_index_1" config: config1 error: &error]);
    
    CBLVectorIndexConfiguration* config2 = [[CBLVectorIndexConfiguration alloc] initWithExpression: @"vector"
                                                                                        dimensions: 300
                                                                                         centroids: 64000];
    AssertNotNil(config2);
    Assert([collection createIndexWithName: @"words_index_2" config: config2 error: &error]);
    
    [self expectException: NSInvalidArgumentException in:^{
        (void) [[CBLVectorIndexConfiguration alloc] initWithExpression: @"vector" 
                                                            dimensions: 300
                                                             centroids: 0];
    }];
    
    [self expectException: NSInvalidArgumentException in:^{
        (void) [[CBLVectorIndexConfiguration alloc] initWithExpression: @"vector" 
                                                            dimensions: 300
                                                             centroids: 64001];
    }];
}

- (void) testCreateVectorIndex {
    NSError* error;
    CBLCollection* collection = [_db collectionWithName: @"words" scope: nil error: &error];
    CBLVectorIndexConfiguration* config = [[CBLVectorIndexConfiguration alloc] initWithExpression: @"vector"
                                                                                       dimensions: 300
                                                                                        centroids: 20];
    Assert([collection createIndexWithName: @"words_index" config: config error: &error]);
    
    NSArray* names = [collection indexes: &error];
    Assert([names containsObject: @"words_index"]);
    
    NSString* sql = @"select meta().id, word from _default.words where vector_match(words_index, $vector, 20)";
    CBLQuery* q = [_db createQuery: sql error: &error];
    
    CBLQueryParameters* parameters = [[CBLQueryParameters alloc] init];
    [parameters setValue: kDinnerVector forName: @"vector"];
    [q setParameters: parameters];
    
    NSString* explain = [q explain: &error];
    Assert([explain rangeOfString: @"SCAN kv_.words:vector:words_index"].location != NSNotFound);
    
    CBLQueryResultSet* rs = [q execute: &error];
    NSArray* allObjects = rs.allObjects;
    AssertEqual(allObjects.count, 20);
}

- (void) testUpdateVectorIndex {
    NSError* error;
    CBLCollection* wordsCollection = [_db collectionWithName: @"words" scope: nil error: &error];
    CBLCollection* extWordsCollection = [_db collectionWithName: @"extwords" scope: nil error: &error];
    
    CBLVectorIndexConfiguration* config = [[CBLVectorIndexConfiguration alloc] initWithExpression: @"vector" 
                                                                                       dimensions: 300
                                                                                        centroids: 8];
    
    Assert([wordsCollection createIndexWithName: @"words_index" config: config error: &error]);
    
    NSArray* names = [wordsCollection indexes: &error];
    Assert([names containsObject: @"words_index"]);
    
    // Query
    NSString* sql = @"select meta().id, word from _default.words where vector_match(words_index, $vector, 350)";
    CBLQuery* q = [_db createQuery: sql error: &error];
    
    CBLQueryParameters* parameters = [[CBLQueryParameters alloc] init];
    [parameters setValue: kDinnerVector forName: @"vector"];
    [q setParameters: parameters];
    
    NSString* explain = [q explain: &error];
    Assert([explain rangeOfString: @"SCAN kv_.words:vector:words_index"].location != NSNotFound);
    
    CBLQueryResultSet* rs = [q execute: &error];
    NSArray* allObjects = rs.allObjects;
    AssertEqual(allObjects.count, 300);
    
    // Update docs:
    NSDictionary* data = [[extWordsCollection documentWithID: @"word1" error : &error] toDictionary];
    CBLMutableDocument* destinationDoc = [self createDocument: @"word351" data: data];
    Assert([wordsCollection saveDocument: destinationDoc error: &error]);
    
    data = [[extWordsCollection documentWithID: @"word2" error : &error] toDictionary];
    destinationDoc = [self createDocument: @"word352" data:data];
    Assert([wordsCollection saveDocument: destinationDoc error: &error]);
    
    data = [[extWordsCollection documentWithID: @"word3" error : &error] toDictionary];
    CBLMutableDocument* destinationDoc2 = [[wordsCollection documentWithID: @"word1" error: &error] toMutable];
    [destinationDoc2 setData: data];
    Assert([wordsCollection saveDocument: destinationDoc2 error: &error]);
    
    [wordsCollection deleteDocument: [wordsCollection documentWithID: @"word2" error :&error] error: &error];
    
    rs = [q execute: &error];
    allObjects = rs.allObjects;
    AssertEqual(allObjects.count, 301);
    
}

// CBL-5444
- (void) _testCreateVectorIndexWithInvalidVectors {
    NSError* error;
    CBLCollection* collection = [_db collectionWithName: @"words" scope: nil error: &error];
    
    // Update docs:
    CBLMutableDocument* auxDoc = [[collection documentWithID: @"word1" error: &error] toMutable];
    [auxDoc setArray: nil forKey: @"vector"];
    [collection saveDocument: auxDoc error: &error];
    
    auxDoc = [[collection documentWithID: @"word2" error: &error] toMutable];
    [auxDoc setString: @"string" forKey: @"vector"];
    [collection saveDocument: auxDoc error: &error];
    
    auxDoc = [[collection documentWithID: @"word3" error: &error] toMutable];
    [auxDoc removeValueForKey: @"vector"];
    [collection saveDocument: auxDoc error: &error];
    
    // CBL-5444
    auxDoc = [[collection documentWithID: @"word4" error: &error] toMutable];
    CBLMutableArray* vector = [auxDoc arrayForKey: @"vector"];
    [vector removeValueAtIndex: 0];
    Assert([collection saveDocument: auxDoc error: &error]);
    
    // Create vector index
    CBLVectorIndexConfiguration* config = [[CBLVectorIndexConfiguration alloc] initWithExpression: @"vector" 
                                                                                       dimensions: 300
                                                                                        centroids: 8];
    Assert([collection createIndexWithName: @"words_index" config: config error: &error]);

    NSArray* names = [collection indexes: &error];
    Assert([names containsObject: @"words_index"]);
    
    // Query:
    NSString* sql = @"select meta().id, word from _default.words where vector_match(words_index, $vector, 350)";
    CBLQuery* q = [_db createQuery: sql error: &error];
    
    CBLQueryParameters* parameters = [[CBLQueryParameters alloc] init];
    [parameters setValue: kDinnerVector forName: @"vector"];
    [q setParameters: parameters];
    
    NSString* explain = [q explain: &error];
    Assert([explain rangeOfString: @"SCAN kv_.words:vector:words_index"].location != NSNotFound);
    
    CBLQueryResultSet* rs = [q execute: &error];
    NSArray* allObjects = rs.allObjects;
    AssertEqual(allObjects.count, 296);
    
    auxDoc = [[collection documentWithID: @"word5" error: &error] toMutable];
    [auxDoc setString: nil forKey: @"vector"];
    [collection saveDocument: auxDoc error: &error];
    rs = [q execute: &error];
    allObjects = rs.allObjects;
    AssertEqual(allObjects.count, 295);
}

- (void) testCreateVectorIndexUsingPredictionModel {
    NSError* error;
    
    CBLCollection* wordsCollection = [_db collectionWithName: @"words" scope: nil error: &error];
    CBLCollection* extWordsCollection = [_db collectionWithName: @"extwords" scope: nil error: &error];
    
    CBLDatabase *modelDb = [self openDBNamed: kDatabaseName error: &error];
    CBLWordEmbeddingModel* model = [[CBLWordEmbeddingModel alloc] initWithDatabase: modelDb];
    [CBLDatabase.prediction registerModel: model withName: @"WordEmbedding"];
    
    CBLVectorIndexConfiguration* config = [[CBLVectorIndexConfiguration alloc] initWithExpression: @"prediction(\"WordEmbedding\",{\"word\": word}).vector" 
                                                                                       dimensions: 300
                                                                                        centroids: 8];
    Assert([wordsCollection createIndexWithName: @"words_pred_index" config: config error: &error]);
    
    NSArray* names = [wordsCollection indexes: &error];
    Assert([names containsObject: @"words_pred_index"]);
    
    // Query:
    NSString* sql = @"select meta().id, word from _default.words where vector_match(words_pred_index, $vector, 350)";
    
    CBLQueryParameters* parameters = [[CBLQueryParameters alloc] init];
    [parameters setValue: kDinnerVector forName: @"vector"];
    
    CBLQuery* q = [_db createQuery: sql error: &error];
    [q setParameters: parameters];
    
    NSString* explain = [q explain: &error];
    Assert([explain rangeOfString: @"SCAN kv_.words:vector:words_pred_index"].location != NSNotFound);
    CBLQueryResultSet* rs = [q execute: &error];
    NSArray* allObjects = rs.allObjects;
    AssertEqual(allObjects.count, 300);
    
    // Create words.word301 with extwords.word1 content
    NSDictionary* data = [[extWordsCollection documentWithID: @"word1" error : &error] toDictionary];
    CBLMutableDocument* destinationDoc = [self createDocument: @"word301" data: data];
    Assert([wordsCollection saveDocument: destinationDoc error: &error]);
    
    // Create words.word302 with extwords.word2 content
    data = [[extWordsCollection documentWithID: @"word2" error : &error] toDictionary];
    destinationDoc = [self createDocument: @"word302" data: data];
    Assert([wordsCollection saveDocument: destinationDoc error: &error]);
    
    // Update words.word1 with extwords.word3 content
    data = [[extWordsCollection documentWithID: @"word3" error : &error] toDictionary];
    CBLMutableDocument* destinationDoc2 = [[wordsCollection documentWithID: @"word1" error: &error] toMutable];
    [destinationDoc2 setData: data];
    Assert([wordsCollection saveDocument: destinationDoc2 error: &error]);
    
    // Delete words.word2
    [wordsCollection deleteDocument: [wordsCollection documentWithID: @"word2" error : &error] error: &error];
    
    rs = [q execute: &error];
    allObjects = rs.allObjects;
    AssertEqual(allObjects.count, 301);
    
    [CBLDatabase.prediction unregisterModelWithName: @"WordEmbedding"];
}

// CBL-5444 + CBL-5453
- (void) _testCreateVectorIndexUsingPredictionModelWithInvalidVectors {
    NSError* error;
    CBLCollection* collection = [_db collectionWithName: @"words" scope: nil error: &error];
    
    CBLDatabase *modelDb = [self openDBNamed: kDatabaseName error: &error];
    CBLWordEmbeddingModel* model = [[CBLWordEmbeddingModel alloc] initWithDatabase: modelDb];
    [CBLDatabase.prediction registerModel: model withName: @"WordEmbedding"];
    
    // Update docs:
    CBLMutableDocument* auxDoc = [[collection documentWithID: @"word1" error: &error] toMutable];
    [auxDoc setArray: nil forKey: @"vector"];
    Assert([collection saveDocument: auxDoc error: &error]);
    
    auxDoc = [[collection documentWithID: @"word2" error: &error] toMutable];
    [auxDoc setString: @"string" forKey: @"vector"];
    Assert([collection saveDocument:auxDoc error:&error]);
    
    auxDoc = [[collection documentWithID: @"word3" error: &error] toMutable];
    [auxDoc removeValueForKey: @"vector"];
    Assert([collection saveDocument:auxDoc error:&error]);

    // CBL-5444
    auxDoc = [[collection documentWithID: @"word4" error: &error] toMutable];
    CBLMutableArray* vector = [auxDoc arrayForKey: @"vector"];
    [vector removeValueAtIndex: 0];
    Assert([collection saveDocument: auxDoc error: &error]);

    // Create vector index
    CBLVectorIndexConfiguration* config = [[CBLVectorIndexConfiguration alloc] initWithExpression: @"prediction(\"WordEmbedding\",{\"word\": word}).vector" 
                                                                                       dimensions: 300
                                                                                        centroids: 8];
    Assert([collection createIndexWithName: @"words_pred_index" config: config error: &error]);
    
    NSArray* names = [collection indexes: &error];
    Assert([names containsObject: @"words_pred_index"]);

    // Query:
    NSString* sql = @"select meta().id, word from _default.words where vector_match(words_pred_index, $vector, 350)";
    CBLQuery* q = [_db createQuery: sql error: &error];
    
    CBLQueryParameters* parameters = [[CBLQueryParameters alloc] init];
    [parameters setValue: kDinnerVector forName: @"vector"];
    [q setParameters: parameters];
    
    NSString* explain = [q explain: &error];
    Assert([explain rangeOfString: @"SCAN kv_.words:vector:words_pred_index"].location != NSNotFound);
    CBLQueryResultSet* rs = [q execute: &error];
    NSArray* allObjects = rs.allObjects;
    AssertEqual(allObjects.count, 296);
    
    auxDoc = [[collection documentWithID: @"word5" error: &error] toMutable];
    [auxDoc setArray: nil forKey: @"vector"];
    Assert([collection saveDocument: auxDoc error: &error]);

    // CBL-5453
    rs = [q execute: &error];
    allObjects = rs.allObjects;
    AssertEqual(allObjects.count, 295);
    
    [CBLDatabase.prediction unregisterModelWithName: @"WordEmbedding"];
}

- (void) testCreateVectorIndexWithSQ {
    NSError* error;
    CBLCollection* collection = [_db collectionWithName: @"words" scope: nil error: &error];
    
    // Create vector index
    CBLVectorIndexConfiguration* config = [[CBLVectorIndexConfiguration alloc] initWithExpression: @"vector" 
                                                                                       dimensions: 300
                                                                                        centroids: 20];
    config.encoding = [CBLVectorEncoding scalarQuantizerWithType: kCBLSQ4];
    Assert([collection createIndexWithName: @"words_index" config: config error: &error]);
    
    NSArray* names = [collection indexes: &error];
    Assert([names containsObject: @"words_index"]);
    
    // Query:
    NSString* sql = @"select meta().id, word from _default.words where vector_match(words_index, $vector, 20)";
    CBLQuery* q = [_db createQuery: sql error: &error];
    
    CBLQueryParameters* parameters = [[CBLQueryParameters alloc] init];
    [parameters setValue: kDinnerVector forName: @"vector"];
    [q setParameters: parameters];
    
    NSString* explain = [q explain: &error];
    Assert([explain rangeOfString: @"SCAN kv_.words:vector:words_index"].location != NSNotFound);
    CBLQueryResultSet* rs = [q execute: &error];
    NSArray* allObjects = rs.allObjects;
    AssertEqual(allObjects.count, 20);
    
    // Repeat using SQ6
    [collection deleteIndexWithName: @"words_index" error: &error];
    config.encoding = [CBLVectorEncoding scalarQuantizerWithType: kCBLSQ6];
    Assert([collection createIndexWithName: @"words_index" config: config error: &error]);
    
    // Rerun query:
    rs = [q execute: &error];
    allObjects = rs.allObjects;
    AssertEqual(allObjects.count, 20);
    
    // Repeat using SQ8
    [collection deleteIndexWithName: @"words_index" error: &error];
    config.encoding = [CBLVectorEncoding scalarQuantizerWithType: kCBLSQ8];
    Assert([collection createIndexWithName: @"words_index" config: config error: &error]);
    
    // Rerun query:
    rs = [q execute: &error];
    allObjects = rs.allObjects;
    AssertEqual(allObjects.count, 20);
}

- (void) testCreateVectorIndexWithNoneEncoding {
    NSError* error;
    CBLCollection* collection = [_db collectionWithName: @"words" scope: nil error: &error];
    
    // Create vector index
    CBLVectorIndexConfiguration* config = [[CBLVectorIndexConfiguration alloc] initWithExpression: @"vector"
                                                                                       dimensions: 300
                                                                                        centroids: 20];
    config.encoding = [CBLVectorEncoding none];
    Assert([collection createIndexWithName: @"words_index" config: config error: &error]);
    
    NSArray* names = [collection indexes: &error];
    Assert([names containsObject: @"words_index"]);
    
    // Query:
    NSString* sql = @"select meta().id, word from _default.words where vector_match(words_index, $vector, 20)";
    CBLQuery* q = [_db createQuery: sql error: &error];
    
    CBLQueryParameters* parameters = [[CBLQueryParameters alloc] init];
    [parameters setValue: kDinnerVector forName: @"vector"];
    [q setParameters: parameters];
    
    NSString* explain = [q explain: &error];
    Assert([explain rangeOfString: @"SCAN kv_.words:vector:words_index"].location != NSNotFound);
    CBLQueryResultSet* rs = [q execute: &error];
    NSArray* allObjects = rs.allObjects;
    AssertEqual(allObjects.count, 20);
}

- (void) testCreateVectorIndexWithPQ {
    NSError* error;
    CBLCollection* collection = [_db collectionWithName: @"words" scope: nil error: &error];
    
    int bitsValues[3] = {8, 4, 12};
    for (size_t i = 0; i < sizeof(bitsValues)/sizeof(int); i++) {
        // Create vector index
        CBLVectorIndexConfiguration* config = [[CBLVectorIndexConfiguration alloc] initWithExpression: @"vector"
                                                                                           dimensions: 300
                                                                                            centroids: 20];
        config.encoding = [CBLVectorEncoding productQuantizerWithSubquantizers: 5
                                                                          bits: bitsValues[i]];
        Assert([collection createIndexWithName: @"words_index" config: config error: &error]);
        
        NSArray* names = [collection indexes: &error];
        Assert([names containsObject: @"words_index"]);
        
        // Query:
        NSString* sql = @"select meta().id, word from _default.words where vector_match(words_index, $vector, 20)";
        CBLQuery* q = [_db createQuery: sql error: &error];
        
        CBLQueryParameters* parameters = [[CBLQueryParameters alloc] init];
        [parameters setValue: kDinnerVector forName: @"vector"];
        [q setParameters: parameters];
        
        NSString* explain = [q explain: &error];
        Assert([explain rangeOfString: @"SCAN kv_.words:vector:words_index"].location != NSNotFound);
        CBLQueryResultSet* rs = [q execute: &error];
        NSArray* allObjects = rs.allObjects;
        AssertEqual(allObjects.count, 20);
        
        // Delete index
        [collection deleteIndexWithName: @"words_index" error: &error];
    }
}

// CBL-5459
- (void) _testSubquantizersValidation {
    NSError* error;
    CBLCollection* collection = [_db collectionWithName: @"words" scope: nil error: &error];
    
    // Create vector index
    CBLVectorIndexConfiguration* config = [[CBLVectorIndexConfiguration alloc] initWithExpression: @"vector"
                                                                                       dimensions: 300
                                                                                        centroids: 20];
    config.encoding = [CBLVectorEncoding productQuantizerWithSubquantizers: 1
                                                                      bits: 8];
    Assert([collection createIndexWithName: @"words_index" config: config error: &error]);
    
    NSArray* names = [collection indexes: &error];
    Assert([names containsObject: @"words_index"]);
    
    // Check if valid values
    int goodValues[17] = {2, 3, 4, 5, 6, 10, 12, 15, 20, 25, 30, 50, 60, 75, 100, 150, 300};
    for (size_t i = 0; i < sizeof(goodValues)/sizeof(int); i++) {
        [collection deleteIndexWithName: @"words_index" error: &error];
        config.encoding = [CBLVectorEncoding productQuantizerWithSubquantizers: goodValues[i]
                                                                          bits: 8];
        Assert([collection createIndexWithName: @"words_index" config: config error: &error]);
    }
    
    // Check if exception thrown for wrong values
    [self expectException: NSInvalidArgumentException in:^{
        int wrongValues[2] = {0, 7};
        for (size_t i = 0; i < sizeof(wrongValues)/sizeof(int); i++) {
            [collection deleteIndexWithName: @"words_index" error: nil];
            config.encoding = [CBLVectorEncoding productQuantizerWithSubquantizers: wrongValues[i]
                                                                              bits: 8];
            [collection createIndexWithName: @"words_index" config: config error: nil];
        }
    }];
}

- (void) testeCreateVectorIndexWithFixedTrainingSize {
    NSError* error;
    CBLCollection* collection = [_db collectionWithName: @"words" scope: nil error: &error];
    
    // Create vector index
    CBLVectorIndexConfiguration* config = [[CBLVectorIndexConfiguration alloc] initWithExpression: @"vector"
                                                                                       dimensions: 300
                                                                                        centroids: 20];
    config.minTrainingSize = 100;
    config.maxTrainingSize = 100;
    Assert([collection createIndexWithName: @"words_index" config: config error: &error]);
    
    NSArray* names = [collection indexes: &error];
    Assert([names containsObject: @"words_index"]);
    
    // Query:
    NSString* sql = @"select meta().id, word from _default.words where vector_match(words_index, $vector, 20)";
    CBLQuery* q = [_db createQuery: sql error: &error];
    
    CBLQueryParameters* parameters = [[CBLQueryParameters alloc] init];
    [parameters setValue: kDinnerVector forName: @"vector"];
    [q setParameters: parameters];
    
    NSString* explain = [q explain: &error];
    Assert([explain rangeOfString: @"SCAN kv_.words:vector:words_index"].location != NSNotFound);
    CBLQueryResultSet* rs = [q execute: &error];
    NSArray* allObjects = rs.allObjects;
    AssertEqual(allObjects.count, 20);
}

- (void) testValidateMinMaxTrainingSize {
    NSError* error;
    CBLCollection* collection = [_db collectionWithName: @"words" scope: nil error: &error];
    
    // Create vector index
    CBLVectorIndexConfiguration* config = [[CBLVectorIndexConfiguration alloc] initWithExpression: @"vector"
                                                                                       dimensions: 300
                                                                                        centroids: 20];
    config.minTrainingSize = 1;
    config.maxTrainingSize = 100;
    Assert([collection createIndexWithName: @"words_index" config: config error: &error]);
    
    NSArray* names = [collection indexes: &error];
    Assert([names containsObject: @"words_index"]);
    
    // Check if exception thrown for wrong values
    [self expectException: NSInvalidArgumentException in:^{
        int minTrainingValues[3] = {0, 0, 10};
        int maxTrainingValues[3] = {0, 100, 9};
        for (size_t i = 0; i < sizeof(minTrainingValues)/sizeof(int); i++) {
            [collection deleteIndexWithName: @"words_index" error: nil];
            config.minTrainingSize = minTrainingValues[i];
            config.maxTrainingSize = maxTrainingValues[i];
            [collection createIndexWithName: @"words_index" config: config error: nil];
        }
    }];
}

- (void) testQueryUntrainedVectorIndex {
    NSError* error;
    CBLCollection* collection = [_db collectionWithName: @"words" scope: nil error: &error];
    
    // Create vector index
    CBLVectorIndexConfiguration* config = [[CBLVectorIndexConfiguration alloc] initWithExpression: @"vector"
                                                                                       dimensions: 300
                                                                                        centroids: 20];
    // out of bounds (300 words in db)
    config.minTrainingSize = 400;
    config.maxTrainingSize = 500;
    Assert([collection createIndexWithName: @"words_index" config: config error: &error]);
    
    NSArray* names = [collection indexes: &error];
    Assert([names containsObject: @"words_index"]);
    
    // Query:
    NSString* sql = @"select meta().id, word from _default.words where vector_match(words_index, $vector, 20)";
    CBLQuery* q = [_db createQuery: sql error: &error];
    
    CBLQueryParameters* parameters = [[CBLQueryParameters alloc] init];
    [parameters setValue: kDinnerVector forName: @"vector"];
    [q setParameters: parameters];
    
    NSString* explain = [q explain: &error];
    Assert([explain rangeOfString: @"SCAN kv_.words:vector:words_index"].location != NSNotFound);
    CBLQueryResultSet* rs = [q execute: &error];
    NSArray* allObjects = rs.allObjects;
    AssertEqual(allObjects.count, 20);
}

- (void) testCreateVectorIndexWithCosineDistance {
    NSError* error;
    CBLCollection* collection = [_db collectionWithName: @"words" scope: nil error: &error];
    
    // Create vector index
    CBLVectorIndexConfiguration* config = [[CBLVectorIndexConfiguration alloc] initWithExpression: @"vector"
                                                                                       dimensions: 300
                                                                                        centroids: 20];
    config.metric = kCBLDistanceMetricCosine;
    Assert([collection createIndexWithName: @"words_index" config: config error: &error]);
    
    NSArray* names = [collection indexes: &error];
    Assert([names containsObject: @"words_index"]);
    
    // Query:
    NSString* sql = @"select meta().id, word, vector_distance(words_index) from _default.words where vector_match(words_index, $vector, 20)";
    CBLQuery* q = [_db createQuery: sql error: &error];
    
    CBLQueryParameters* parameters = [[CBLQueryParameters alloc] init];
    [parameters setValue: kDinnerVector forName: @"vector"];
    [q setParameters: parameters];
    
    NSString* explain = [q explain: &error];
    Assert([explain rangeOfString: @"SCAN kv_.words:vector:words_index"].location != NSNotFound);
    CBLQueryResultSet* rs = [q execute: &error];
    NSArray* allObjects = rs.allResults;
    AssertEqual(allObjects.count, 20);
    
    for(CBLQueryResult* result in rs){
        // doubleAtIndex: vector_distance(words_index)
        Assert([result doubleAtIndex: 3] > 0);
        Assert([result doubleAtIndex: 3] < 1);
    }
}

- (void) testCreateVectorIndexWithEuclideanDistance {
    NSError* error;
    CBLCollection* collection = [_db collectionWithName: @"words" scope: nil error: &error];
    
    // Create vector index
    CBLVectorIndexConfiguration* config = [[CBLVectorIndexConfiguration alloc] initWithExpression: @"vector"
                                                                                       dimensions: 300
                                                                                        centroids: 20];
    config.metric = kCBLDistanceMetricEuclidean;
    Assert([collection createIndexWithName: @"words_index" config: config error: &error]);
    
    NSArray* names = [collection indexes: &error];
    Assert([names containsObject: @"words_index"]);
    
    // Query:
    NSString* sql = @"select meta().id, word, vector_distance(words_index) from _default.words where vector_match(words_index, $vector, 20)";
    CBLQuery* q = [_db createQuery: sql error: &error];
    
    CBLQueryParameters* parameters = [[CBLQueryParameters alloc] init];
    [parameters setValue: kDinnerVector forName: @"vector"];
    [q setParameters: parameters];
    
    NSString* explain = [q explain: &error];
    Assert([explain rangeOfString: @"SCAN kv_.words:vector:words_index"].location != NSNotFound);
    CBLQueryResultSet* rs = [q execute: &error];
    NSArray* allObjects = rs.allResults;
    AssertEqual(allObjects.count, 20);
    
    for(CBLQueryResult* result in rs){
        // doubleAtIndex: vector_distance(words_index)
        Assert([result doubleAtIndex: 3] > 0);
    }
}

- (void) testCreateVectorIndexWithExistingName {
    NSError* error;
    CBLCollection* collection = [_db collectionWithName: @"words" scope: nil error: &error];
    
    // Create and recreate vector index using the same config
    CBLVectorIndexConfiguration* config = [[CBLVectorIndexConfiguration alloc] initWithExpression: @"vector"
                                                                                       dimensions: 300
                                                                                        centroids: 20];
    Assert([collection createIndexWithName: @"words_index" config: config error: &error]);
    Assert([collection createIndexWithName: @"words_index" config: config error: &error]);
    
    // Recreate index with same name using different config
    CBLVectorIndexConfiguration* config2 = [[CBLVectorIndexConfiguration alloc] initWithExpression: @"vectors"
                                                                                       dimensions: 300
                                                                                        centroids: 20];
    Assert([collection createIndexWithName: @"words_index" config: config2 error: &error]);
}

- (void) testDeleteVectorIndex {
    NSError* error;
    CBLCollection* collection = [_db collectionWithName: @"words" scope: nil error: &error];
    
    // Create and recreate vector index using the same config
    CBLVectorIndexConfiguration* config = [[CBLVectorIndexConfiguration alloc] initWithExpression: @"vector"
                                                                                       dimensions: 300
                                                                                        centroids: 20];
    Assert([collection createIndexWithName: @"words_index" config: config error: &error]);
    
    NSArray* names = [collection indexes: &error];
    Assert([names containsObject: @"words_index"]);
    
    // Query:
    NSString* sql = @"select meta().id, word from _default.words where vector_match(words_index, $vector, 20)";
    CBLQuery* q = [_db createQuery: sql error: &error];
    
    CBLQueryParameters* parameters = [[CBLQueryParameters alloc] init];
    [parameters setValue: kDinnerVector forName: @"vector"];
    [q setParameters: parameters];
    
    NSString* explain = [q explain: &error];
    Assert([explain rangeOfString: @"SCAN kv_.words:vector:words_index"].location != NSNotFound);
    CBLQueryResultSet* rs = [q execute: &error];
    NSArray* allObjects = rs.allResults;
    AssertEqual(allObjects.count, 20);
    
    // Delete index
    [collection deleteIndexWithName: @"words_index" error: &error];
    
    names = [collection indexes: &error];
    AssertEqual(names.count, 0);
}

// CBL-5466
- (void) _testVectorMatchOnNonExistingIndex {
    NSError* vectorError;
    [_db createQuery: @"select meta().id, word from _default.words where vector_match(words_index, $vector, 20)" 
               error: &vectorError];
    
    NSError* ftsError;
    [self.db createQuery: @"select meta().id, word from _default.words where match(fts_words_index, 'word')"
                   error: &ftsError];
    
    AssertEqualObjects(vectorError, ftsError);
    AssertEqual(vectorError.domain, CBLErrorDomain);
    AssertEqual(vectorError.code, CBLErrorMissingIndex);
}

// CBL-5465
- (void) _testVectorMatchDefaultLimit {
    NSError* error;
    CBLCollection* collection = [_db collectionWithName: @"words" scope: nil error: nil];
    
    // Create index
    CBLVectorIndexConfiguration* config = [[CBLVectorIndexConfiguration alloc] initWithExpression: @"vector"
                                                                                       dimensions: 300
                                                                                        centroids: 20];
    Assert([collection createIndexWithName: @"words_index" config: config error: &error]);
    
    NSArray* names = [collection indexes: &error];
    Assert([names containsObject: @"words_index"]);
    
    // Query:
    NSString* sql = @"select meta().id, word from _default.words where vector_match(words_index, $vector)";
    CBLQuery* q = [_db createQuery: sql error: &error];
    AssertNil(error);
    
    CBLQueryParameters* parameters = [[CBLQueryParameters alloc] init];
    [parameters setValue: kDinnerVector forName: @"vector"];
    [q setParameters: parameters];
    
    NSString* explain = [q explain: &error];
    Assert([explain rangeOfString: @"SCAN kv_.words:vector:words_index"].location != NSNotFound);
    CBLQueryResultSet* rs = [q execute: &error];
    NSArray* allObjects = rs.allResults;
    AssertEqual(allObjects.count, 3);
}

// CBL-5476
// Error might not be shown
- (void) _testVectorMatchLimitBoundary {
    NSError* error;
    CBLCollection* collection = [_db collectionWithName: @"words" scope: nil error: &error];
    
    // Create index
    CBLVectorIndexConfiguration* config = [[CBLVectorIndexConfiguration alloc] initWithExpression: @"vector"
                                                                                       dimensions: 300
                                                                                        centroids: 20];
    Assert([collection createIndexWithName: @"words_index" config: config error: &error]);
    
    NSArray* names = [collection indexes: &error];
    Assert([names containsObject: @"words_index"]);
    
    // Check valid query with 1 and 10000 set limit
    int goodValues[2] = {1, 10000};
    for (size_t i = 0; i < sizeof(goodValues)/sizeof(int); i++) {
        NSString* sql = [NSString stringWithFormat: @"select meta().id, word from _default.words where vector_match(words_index, $vector, %d)", goodValues[i]];
        [_db createQuery: sql error: &error];
        AssertNil(error);
    }
    
    // Check if exception thrown for wrong limit values
    int wrongValues[3] = {-1, 0, 10001};
    for (size_t i = 0; i < sizeof(wrongValues)/sizeof(int); i++) {
        int currValue =  wrongValues[i];
        [self expectError: CBLErrorDomain code: CBLErrorInvalidQuery in: ^BOOL(NSError** err) {
            return [self.db createQuery: [NSString stringWithFormat:@"select meta().id, word from _default.words where vector_match(words_index, $vector, %d)", currValue]
                                  error: err] != nil;
        }];
    }
}

- (void) testVectorMatchWithAndExpression {
    NSError* error;
    CBLCollection* collection = [_db collectionWithName: @"words" scope: nil error: &error];
    
    // Create index
    CBLVectorIndexConfiguration* config = [[CBLVectorIndexConfiguration alloc] initWithExpression: @"vector"
                                                                                       dimensions: 300
                                                                                        centroids: 2];
    Assert([collection createIndexWithName: @"words_index" config: config error: &error]);
    
    NSArray* names = [collection indexes: &error];
    Assert([names containsObject: @"words_index"]);
    
    // Query with a single AND:
    NSString* sql = @"select meta().id, word, catid from _default.words where vector_match(words_index, $vector, 300) AND catid = 'cat1'";
    CBLQuery* q = [_db createQuery: sql error: &error];
    AssertNil(error);
    
    CBLQueryParameters* parameters = [[CBLQueryParameters alloc] init];
    [parameters setValue: kDinnerVector forName: @"vector"];
    [q setParameters: parameters];
    NSString* explain = [q explain: &error];
    Assert([explain rangeOfString: @"SCAN kv_.words:vector:words_index"].location != NSNotFound);
    CBLQueryResultSet* rs = [q execute: &error];

    NSArray* allObjects = rs.allResults;
    AssertEqual(allObjects.count, 50);
    
    for(CBLQueryResult* result in rs){
        // valueAtIndex: catid
        AssertEqual([result valueAtIndex: 3], @"cat1");
    }
}

- (void) testVectorMatchWithMultipleAndExpression {
    NSError* error;
    CBLCollection* collection = [_db collectionWithName: @"words" scope: nil error: &error];
    
    // Create index
    CBLVectorIndexConfiguration* config = [[CBLVectorIndexConfiguration alloc] initWithExpression: @"vector"
                                                                                       dimensions: 300
                                                                                        centroids: 2];
    Assert([collection createIndexWithName: @"words_index" config: config error: &error]);
    
    NSArray* names = [collection indexes: &error];
    Assert([names containsObject: @"words_index"]);
    
    // Query with mutiple ANDs:
    NSString* sql = @"select meta().id, word, catid from _default.words where (vector_match(words_index, $vector, 300) AND word is valued) AND catid = 'cat1'";
    CBLQuery* q = [_db createQuery: sql error: &error];
    AssertNil(error);
    
    CBLQueryParameters* parameters = [[CBLQueryParameters alloc] init];
    [parameters setValue: kDinnerVector forName: @"vector"];
    [q setParameters: parameters];
    NSString* explain = [q explain: &error];
    Assert([explain rangeOfString: @"SCAN kv_.words:vector:words_index"].location != NSNotFound);
    CBLQueryResultSet* rs = [q execute: &error];

    NSArray* allObjects = rs.allResults;
    AssertEqual(allObjects.count, 50);
    
    for(CBLQueryResult* result in rs){
        // valueAtIndex: catid
        AssertEqual([result valueAtIndex: 3], @"cat1");
    }
}

// CBL-5477
- (void) _testInvalidVectorMatchWithOrExpression {
    NSError* error;
    CBLCollection* collection = [_db collectionWithName: @"words" scope: nil error: &error];
    
    // Create index
    CBLVectorIndexConfiguration* config = [[CBLVectorIndexConfiguration alloc] initWithExpression: @"vector"
                                                                                       dimensions: 300
                                                                                        centroids: 2];
    Assert([collection createIndexWithName: @"words_index" config: config error: &error]);
    
    NSArray* names = [collection indexes: &error];
    Assert([names containsObject: @"words_index"]);
    
    // Query with OR:
    NSString* sql = @"select meta().id, word, catid from _default.words where vector_match(words_index, $vector, 300) OR catid = 'cat1'";
    [self expectError: CBLErrorDomain code: CBLErrorInvalidQuery in: ^BOOL(NSError** err) {
        return [self.db createQuery: sql
                              error: err] != nil;
    }];

}

- (void) testChangeIndexTypeUsingConfigs {
    NSError* error;
    CBLCollection* collection = [_db collectionWithName: @"words" scope: nil error: &error];
    
    // Create and recreate vector index using the same config
    CBLVectorIndexConfiguration* config = [[CBLVectorIndexConfiguration alloc] initWithExpression: @"vector"
                                                                                       dimensions: 300
                                                                                        centroids: 20];
    Assert([collection createIndexWithName: @"words_index" config: config error: &error]);
    Assert([collection createIndexWithName: @"words_index" config: config error: &error]);
    
    // Recreate index with same name using different config - fts config
    CBLFullTextIndexConfiguration* config2 = [[CBLFullTextIndexConfiguration alloc] initWithExpression: @[@"word"]
                                                                                         ignoreAccents: NO 
                                                                                              language: nil];
    Assert([collection createIndexWithName: @"words_index" config: config2 error: &error]);
    
    // Recreate index with same name using different config - value config
    CBLValueIndexConfiguration* config3 = [[CBLValueIndexConfiguration alloc] initWithExpression: @[@"word"]];
    Assert([collection createIndexWithName: @"words_index" config: config3 error: &error]);
}

- (void) testChangeExpressionForEachIndex {
    NSError* error;
    CBLCollection* collection = [_db collectionWithName: @"words" scope: nil error: &error];
    
    // Create-Recreate vector index with different expression
    CBLVectorIndexConfiguration* config = [[CBLVectorIndexConfiguration alloc] initWithExpression: @"vector"
                                                                                       dimensions: 300
                                                                                        centroids: 20];
    Assert([collection createIndexWithName: @"words_index" config: config error: &error]);
    
    config = [[CBLVectorIndexConfiguration alloc] initWithExpression: @"vectors"
                                                          dimensions: 300
                                                           centroids: 20];
    Assert([collection createIndexWithName: @"words_index" config: config error: &error]);
    
    // Create-Recreate fts index with different expression
    CBLFullTextIndexConfiguration* config2 = [[CBLFullTextIndexConfiguration alloc] initWithExpression: @[@"word"]
                                                                                         ignoreAccents: NO
                                                                                              language: nil];
    Assert([collection createIndexWithName: @"fts_words_index" config: config2 error: &error]);
    
    config2 = [[CBLFullTextIndexConfiguration alloc] initWithExpression: @[@"words"]
                                                          ignoreAccents: NO
                                                               language: nil];
    Assert([collection createIndexWithName: @"fts_words_index" config: config2 error: &error]);
    
    // Create-Recreate fts index with different expression
    CBLValueIndexConfiguration* config3 = [[CBLValueIndexConfiguration alloc] initWithExpression: @[@"word"]];
    Assert([collection createIndexWithName: @"value_words_index" config: config3 error: &error]);
    
    config3 = [[CBLValueIndexConfiguration alloc] initWithExpression: @[@"words"]];
    Assert([collection createIndexWithName: @"value_words_index" config: config3 error: &error]);
}

@end
