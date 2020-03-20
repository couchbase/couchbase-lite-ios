//
//  QueryTest.h
//  CouchbaseLite
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

#import "CBLTestCase.h"

#define kDOCID      [CBLQuerySelectResult expression: [CBLQueryMeta id]]
#define kREVID      [CBLQuerySelectResult expression: [CBLQueryMeta revisionID]]
#define kSEQUENCE   [CBLQuerySelectResult expression: [CBLQueryMeta sequence]]

@interface QueryTest : CBLTestCase

/**
 create document
 
 - Parameters:
    - i: index for the document. This value will be saved in `number1` key.
    - num: this number is used to create `number2` key-value, where value = num minus i.
 - returns: document which is created and saved to self.db
 */
- (CBLMutableDocument*) createDocNumbered: (NSInteger)i of: (NSInteger)num;

/**
 creates `x` number of documents. Document will be saved with `number1` and `number2` keys, with
 values index of number and total minus index respectively.
 
 This internally uses the `createDocNumbered` function.
 
 For example, if `num` = 100;
 
 ```
 doc1 = {
    number1 = 1,
    number2 = 99
 },
 
 doc2 = {
    number1 = 2,
    number2 = 98
 }
 ```

- Parameters:
  - num: number of documents to be created.
- returns: list of document(in dictionary)
*/
- (NSArray*) loadNumbers: (NSInteger)num;

/**
 loads all data types through a student document example.
 */
- (void) loadStudents;

- (void) runTestWithNumbers: (NSArray*)numbers cases: (NSArray*)cases;

@end
