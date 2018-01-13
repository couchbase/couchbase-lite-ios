//
//  CBLQueryArrayExpression.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 11/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLQueryExpression;
@class CBLQueryVariableExpression;


NS_ASSUME_NONNULL_BEGIN

@interface CBLQueryArrayExpression : NSObject

/**
 Creates a variable expression that represents an item in the array expression
 (ANY/ANY AND EVERY/EVERY <variable> IN <expr> SATISFIES <expr>).
 
 @param name The variable name.
 @return The variable expression.
 */
+ (CBLQueryVariableExpression*) variableWithName: (NSString*)name;

/**
 Creates an ANY quantified operator (ANY <variable> IN <expr> SATISFIES <expr>)
 to evaluate expressions over an array. The ANY operator returns TRUE
 if at least one of the items in the array satisfies the given satisfies expression.
 
 @param variable The variable expression.
 @param inExpression The IN expression that can be evaluated as an array value.
 @param satisfies The expression to be evaluated with.
 @return The ANY quantifies operator.
 */
+ (CBLQueryExpression*) any: (CBLQueryVariableExpression*)variable
                         in: (CBLQueryExpression*)inExpression
                  satisfies: (CBLQueryExpression*)satisfies;

/**
 Creates an ANY AND EVERY quantified operator (ANY AND EVERY <variable name> IN <expr>
 SATISFIES <expr>) to evaluate expressions over an array. The ANY AND EVERY operator
 returns TRUE if the array is NOT empty, and at least one of the items in the array
 satisfies the given satisfies expression.
 
 @param variable The variable expression.
 @param inExpression The IN expression that can be evaluated as an array value.
 @param satisfies The expression to be evaluated with.
 @return The ANY AND EVERY quantifies operator.
 */
+ (CBLQueryExpression*) anyAndEvery: (CBLQueryVariableExpression*)variable
                                 in: (CBLQueryExpression*)inExpression
                          satisfies: (CBLQueryExpression*)satisfies;

/**
 Creates an EVERY quantified operator (ANY <variable name> IN <expr> SATISFIES <expr>)
 to evaluate expressions over an array. The EVERY operator returns TRUE
 if the array is empty OR every item in the array satisfies the given satisfies expression.
 
 @param variable The variable expression.
 @param inExpression The IN expression that can be evaluated as an array value.
 @param satisfies The expression to be evaluated with.
 @return The EVERY quantifies operator.
 */
+ (CBLQueryExpression*) every: (CBLQueryVariableExpression*)variable
                           in: (CBLQueryExpression*)inExpression
                    satisfies: (CBLQueryExpression*)satisfies;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
