//
//  CBLQueryArrayExpression.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 11/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLQueryExpression;


NS_ASSUME_NONNULL_BEGIN

@interface CBLQueryArrayExpression : NSObject

/**
 Creates a variable expression. The variable are used to represent each item in an array
 in the quantified operators (ANY/ANY AND EVERY/EVERY <variable name> IN <expr> SATISFIES <expr>)
 to evaluate expressions over an array.
 
 @param name The variable name.
 @return The variable expression.
 */
+ (CBLQueryExpression*) variableNamed: (NSString*)name;

/**
 Creates an ANY quantified operator (ANY <variable name> IN <expr> SATISFIES <expr>)
 to evaluate expressions over an array. The ANY operator returns TRUE
 if at least one of the items in the array satisfies the given satisfies expression.
 
 @param variableName The variable name represent to an item in the array.
 @param inExpression The array expression that can be evaluated as an array.
 @param satisfies The expression to be evaluated with.
 @return The ANY quantifies operator.
 */
+ (CBLQueryExpression*) any: (NSString*)variableName
                         in: (id)inExpression
                  satisfies: (CBLQueryExpression*)satisfies;

/**
 Creates an ANY AND EVERY quantified operator (ANY AND EVERY <variable name> IN <expr>
 SATISFIES <expr>) to evaluate expressions over an array. The ANY AND EVERY operator
 returns TRUE if the array is NOT empty, and at least one of the items in the array
 satisfies the given satisfies expression.
 
 @param variableName The variable name represent to an item in the array.
 @param inExpression The array expression that can be evaluated as an array.
 @param satisfies The expression to be evaluated with.
 @return The ANY AND EVERY quantifies operator.
 */
+ (CBLQueryExpression*) anyAndEvery: (NSString*)variableName
                                 in: (id)inExpression
                          satisfies: (CBLQueryExpression*)satisfies;

/**
 Creates an EVERY quantified operator (ANY <variable name> IN <expr> SATISFIES <expr>)
 to evaluate expressions over an array. The EVERY operator returns TRUE
 if the array is empty OR every item in the array satisfies the given satisfies expression.
 
 @param variableName The variable name represent to an item in the array.
 @param inExpression The array expression that can be evaluated as an array.
 @param satisfies The expression to be evaluated with.
 @return The EVERY quantifies operator.
 */
+ (CBLQueryExpression*) every: (NSString*)variableName
                           in: (id)inExpression
                    satisfies: (CBLQueryExpression*)satisfies;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
