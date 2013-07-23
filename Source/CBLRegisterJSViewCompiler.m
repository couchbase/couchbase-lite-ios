//
//  CBLRegisterJSViewCompiler.m
//  CouchbaseLite
//
//  Created by Chris Anderson on 7/10/13.
//
//

#import "CBLRegisterJSViewCompiler.h"
#import "CBLJSViewCompiler.h"
#import "CBLView.h"

void CBLRegisterJSViewCompiler(void) {
    [CBLView setCompiler: [[CBLJSViewCompiler alloc] init]];
}
