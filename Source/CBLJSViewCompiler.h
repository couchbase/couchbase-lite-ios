//
//  CBLJSViewCompiler.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/4/13.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.
//

#import "CBLJSFunction.h"
#import <CouchbaseLite/CBLDatabase.h>
#import <CouchbaseLite/CBLView.h>


/** A view compiler for CouchbaseLite that compiles and runs traditional JavaScript map/reduce functions.
    Requires the JavaScriptCore framework; this is a public system framework on Mac OS but private
    on iOS; so on the latter platform you'll need to link your app with your own copy of
    JavaScriptCore. See <https://github.com/phoboslab/JavaScriptCore-iOS>. */
@interface CBLJSViewCompiler : CBLJSCompiler <CBLViewCompiler>
@end


/** A filter compiler for CouchbaseLite that compiles and runs traditional JavaScript filter functions.
    Requires the JavaScriptCore framework; this is a public system framework on Mac OS but private
    on iOS; so on the latter platform you'll need to link your app with your own copy of
    JavaScriptCore. See <https://github.com/phoboslab/JavaScriptCore-iOS>. */
@interface CBLJSFilterCompiler : CBLJSCompiler <CBLFilterCompiler>
@end
