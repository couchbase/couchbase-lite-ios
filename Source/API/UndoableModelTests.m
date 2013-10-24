//
//  UndoableModelTests.m
//  CouchbaseLite
//
//  Created by Zymantas on 2013-10-24.
//
//

#import "CBLUndoableModel.h"
#import "CouchbaseLitePrivate.h"
#import "CBLModelArray.h"
#import "CBLInternal.h"

#if DEBUG

static CBLDatabase* createEmptyDB(void) {
    CBLManager* dbmgr = [CBLManager sharedInstance];
    CAssert(dbmgr);
    NSError* error;
    CBLDatabase* db = [dbmgr createEmptyDatabaseNamed: @"test_db" error: &error];
    CAssert(db, @"Couldn't create db: %@", error);
    return db;
}


static void closeTestDB(CBLDatabase* db) {
    CAssert(db != nil);
    CAssert([db close]);
}

@interface UndoableTestModel : CBLUndoableModel
@property int number;
@property NSString* str;
@property NSData* data;
@property NSDate* date;
@property NSDecimalNumber* decimal;
@property UndoableTestModel* other;
@property NSArray* strings;
@property NSArray* dates;
@property NSArray* others;

@property unsigned reloadCount;
@end


@implementation UndoableTestModel

@dynamic number, str, data, date, decimal, other, strings, dates, others;
@synthesize reloadCount;

- (void) didLoadFromDocument {
    self.reloadCount++;
    Log(@"reloadCount = %u",self.reloadCount);
}

+ (Class) othersItemClass {
    return [UndoableTestModel class];
}

+ (Class) datesItemClass {
    return [NSDate class];
}

TestCase(API_UndoManager) {
    CBLDatabase* db = createEmptyDB();
    db.undoManager = [[NSUndoManager alloc] init];
    
    NSError* error;
    {
        UndoableTestModel* model = [[UndoableTestModel alloc] initWithNewDocumentInDatabase: db];
        model.number = 1337;
        
        CAssert([model save: &error], @"Initial failed: %@", error);
        
        [db.undoManager undo];
        CAssertEq(model.number, 0);
        CAssertNil(model.document);
        
        [db.undoManager redo];
        CAssertEq(model.number, 1337);
        CAssert(model.document != nil);
        
        CAssert([model deleteDocument:nil], @"Document delete failed: %@", error);
        
        [db.undoManager undo];
        CAssertEq(model.number, 1337);
        CAssert(model.document != nil);
        
        [db.undoManager redo];
        CAssertEq(model.number, 0);
        CAssertNil(model.document);
    }
    {
        UndoableTestModel* model = [[UndoableTestModel alloc] initWithNewDocumentInDatabase: db];
        [db.undoManager endUndoGrouping];
        
        [db.undoManager beginUndoGrouping];
        NSData* attData = [@"Ceci n'est pas une pipe." dataUsingEncoding: NSUTF8StringEncoding];
        
        CBLAttachment* attachment = [[CBLAttachment alloc] initWithContentType: @"text/plain"
                                                                          body: attData];
        [model addAttachment: attachment named: @"Caption.txt"];
        CAssert([model save: &error], @"Save after adding attachment failed: %@", error);
        [db.undoManager undo];
        CAssertNil([model attachmentNamed: @"Caption.txt"]);
        [db.undoManager redo];
        CAssert([model attachmentNamed: @"Caption.txt"] != nil);
        
        [model removeAttachmentNamed: @"Caption.txt"];
        CAssertNil([model attachmentNamed: @"Caption.txt"]);
        [db.undoManager undo];
        CAssert([model attachmentNamed: @"Caption.txt"] != nil);
    }
    
    closeTestDB(db);
}


TestCase(API_UndoableModel) {
    RequireTestCase(API_UndoManager);
}

@end

#endif // DEBUG
