//
//  CollectionUtils.m
//  MYUtilities
//
//  Created by Jens Alfke on 1/5/08.
//  Copyright 2008 Jens Alfke. All rights reserved.
//

#import "CollectionUtils.h"
#import "Test.h"


NSDictionary* _dictof(const struct _dictpair* pairs, size_t count)
{
    CAssert(count<10000);
    id objects[count], keys[count];
    size_t n = 0;
    for( size_t i=0; i<count; i++,pairs++ ) {
        if( pairs->value ) {
            objects[n] = pairs->value;
            keys[n] = pairs->key;
            n++;
        }
    }
    return [NSDictionary dictionaryWithObjects: objects forKeys: keys count: n];
}


NSMutableDictionary* _mdictof(const struct _dictpair* pairs, size_t count)
{
    CAssert(count<10000);
    id objects[count], keys[count];
    size_t n = 0;
    for( size_t i=0; i<count; i++,pairs++ ) {
        if( pairs->value ) {
            objects[n] = pairs->value;
            keys[n] = pairs->key;
            n++;
        }
    }
    return [NSMutableDictionary dictionaryWithObjects: objects forKeys: keys count: n];
}


NSArray* $apply( NSArray *src, SEL selector, id defaultValue )
{
    NSMutableArray *dst = [NSMutableArray arrayWithCapacity: src.count];
    for( id obj in src ) {
        id result = [obj performSelector: selector] ?: defaultValue;
        [dst addObject: result];
    }
    return dst;
}

NSArray* $applyKeyPath( NSArray *src, NSString *keyPath, id defaultValue )
{
    NSMutableArray *dst = [NSMutableArray arrayWithCapacity: src.count];
    for( id obj in src ) {
        id result = [obj valueForKeyPath: keyPath] ?: defaultValue;
        [dst addObject: result];
    }
    return dst;
}


BOOL $equal(id obj1, id obj2)      // Like -isEqual: but works even if either/both are nil
{
    if( obj1 )
        return obj2 && [obj1 isEqual: obj2];
    else
        return obj2==nil;
}


NSValue* _box(const void *value, const char *encoding)
{
    // file:///Developer/Documentation/DocSets/com.apple.ADC_Reference_Library.DeveloperTools.docset/Contents/Resources/Documents/documentation/DeveloperTools/gcc-4.0.1/gcc/Type-encoding.html
    char e = encoding[0];
    if( e=='r' )                // ignore 'const' modifier
        e = encoding[1];
    switch( e ) {
        case 'B':   return [NSNumber numberWithBool: *(BOOL*)value];
        case 'c':   return [NSNumber numberWithChar: *(char*)value];
        case 'C':   return [NSNumber numberWithUnsignedChar: *(char*)value];
        case 's':   return [NSNumber numberWithShort: *(short*)value];
        case 'S':   return [NSNumber numberWithUnsignedShort: *(unsigned short*)value];
        case 'i':   return [NSNumber numberWithInt: *(int*)value];
        case 'I':   return [NSNumber numberWithUnsignedInt: *(unsigned int*)value];
        case 'l':   return [NSNumber numberWithLong: *(long*)value];
        case 'L':   return [NSNumber numberWithUnsignedLong: *(unsigned long*)value];
        case 'q':   return [NSNumber numberWithLongLong: *(long long*)value];
        case 'Q':   return [NSNumber numberWithUnsignedLongLong: *(unsigned long long*)value];
        case 'f':   return [NSNumber numberWithFloat: *(float*)value];
        case 'd':   return [NSNumber numberWithDouble: *(double*)value];
        case '*':   return [NSString stringWithUTF8String: *(char**)value];
        case '@':   return *(id*)value;
        default:    return [NSValue value: value withObjCType: encoding];
    }
}


id _cast( Class requiredClass, id object )
{
    if( object && ! [object isKindOfClass: requiredClass] )
        [NSException raise: NSInvalidArgumentException format: @"%@ required, but got %@ %p",
         requiredClass,[object class],object];
    return object;
}

id _castNotNil( Class requiredClass, id object )
{
    if( ! [object isKindOfClass: requiredClass] )
        [NSException raise: NSInvalidArgumentException format: @"%@ required, but got %@ %p",
         requiredClass,[object class],object];
    return object;
}

id _castIf( Class requiredClass, id object )
{
    if( object && ! [object isKindOfClass: requiredClass] )
        object = nil;
    return object;
}

NSArray* _castArrayOf(Class itemClass, NSArray *a)
{
    id item;
    foreach( item, $cast(NSArray,a) )
        _cast(itemClass,item);
    return a;
}


void setObj( id *var, id value )
{
    if( value != *var ) {
        [*var release];
        *var = [value retain];
    }
}

BOOL ifSetObj( id *var, id value )
{
    if( value != *var && ![value isEqual: *var] ) {
        [*var release];
        *var = [value retain];
        return YES;
    } else {
        return NO;
    }
}

void setObjCopy( id *var, id valueToCopy ) {
    if( valueToCopy != *var ) {
        [*var release];
        *var = [valueToCopy copy];
    }
}

BOOL ifSetObjCopy( id *var, id value )
{
    if( value != *var && ![value isEqual: *var] ) {
        [*var release];
        *var = [value copy];
        return YES;
    } else {
        return NO;
    }
}


NSString* $string( const char *utf8Str )
{
    if( utf8Str )
        return [NSString stringWithCString: utf8Str encoding: NSUTF8StringEncoding];
    else
        return nil;
}


BOOL kvSetObj( id owner, NSString *property, id *varPtr, id value )
{
    if( *varPtr != value && ![*varPtr isEqual: value] ) {
        [owner willChangeValueForKey: property];
        [*varPtr autorelease];
        *varPtr = [value retain];
        [owner didChangeValueForKey: property];
        return YES;
    } else {
        return NO;
    }
}


BOOL kvSetObjCopy( id owner, NSString *property, id *varPtr, id value )
{
    if( *varPtr != value && ![*varPtr isEqual: value] ) {
        [owner willChangeValueForKey: property];
        [*varPtr autorelease];
        *varPtr = [value copy];
        [owner didChangeValueForKey: property];
        return YES;
    } else {
        return NO;
    }
}


BOOL kvSetSet( id owner, NSString *property, NSMutableSet *set, NSSet *newSet ) {
    CAssert(set);
    if (!newSet)
        newSet = [NSSet set];
    if (![set isEqualToSet: newSet]) {
        [owner willChangeValueForKey: property
                     withSetMutation:NSKeyValueSetSetMutation 
                        usingObjects:newSet]; 
        [set setSet: newSet];
        [owner didChangeValueForKey: property 
                    withSetMutation:NSKeyValueSetSetMutation 
                       usingObjects:newSet]; 
        return YES;
    } else
        return NO;
}


BOOL kvAddToSet( id owner, NSString *property, NSMutableSet *set, id objToAdd ) {
    CAssert(set);
    if (![set containsObject: objToAdd]) {
        NSSet *changedObjects = [[NSSet alloc] initWithObjects: &objToAdd count: 1];
        [owner willChangeValueForKey: property
                     withSetMutation: NSKeyValueUnionSetMutation 
                        usingObjects: changedObjects]; 
        [set addObject: objToAdd];
        [owner didChangeValueForKey: property 
                    withSetMutation: NSKeyValueUnionSetMutation 
                       usingObjects: changedObjects]; 
        [changedObjects release];
        return YES;
    } else
        return NO;
}


BOOL kvRemoveFromSet( id owner, NSString *property, NSMutableSet *set, id objToRemove ) {
    if ([set containsObject: objToRemove]) {
        NSSet *changedObjects = [[NSSet alloc] initWithObjects: &objToRemove count: 1];
        [owner willChangeValueForKey: property
                     withSetMutation: NSKeyValueMinusSetMutation 
                        usingObjects: changedObjects]; 
        [set removeObject: objToRemove];
        [owner didChangeValueForKey: property 
                    withSetMutation: NSKeyValueMinusSetMutation 
                       usingObjects: changedObjects]; 
        [changedObjects release];
        return YES;
    } else
        return NO;
}


@implementation NSObject (MYUtils)
- (NSString*) my_compactDescription
{
    return [self description];
}
@end


@implementation NSArray (MYUtils)

- (BOOL) my_containsObjectIdenticalTo: (id)object
{
    return [self indexOfObjectIdenticalTo: object] != NSNotFound;
}

- (NSArray*) my_arrayByApplyingSelector: (SEL)selector
{
    return [self my_arrayByApplyingSelector: selector withObject: nil];
}

- (NSArray*) my_arrayByApplyingSelector: (SEL)selector withObject: (id)object
{
    NSUInteger count = [self count];
    NSMutableArray *temp = [[NSMutableArray alloc] initWithCapacity: count];
    NSArray *result;
    NSUInteger i;
    for( i=0; i<count; i++ )
        [temp addObject: [[self objectAtIndex: i] performSelector: selector withObject: object]];
    result = [NSArray arrayWithArray: temp];
    [temp release];
    return result;
}

#if NS_BLOCKS_AVAILABLE
- (NSArray*) my_map: (id (^)(id obj))block {
    NSMutableArray* mapped = [[NSMutableArray alloc] initWithCapacity: self.count];
    for (id obj in self) {
        obj = block(obj);
        if (obj)
            [mapped addObject: obj];
    }
    NSArray* result = [[mapped copy] autorelease];
    [mapped release];
    return result;
}

- (NSArray*) my_filter: (int (^)(id obj))block {
    NSMutableArray* filtered = [[NSMutableArray alloc] initWithCapacity: self.count];
    for (id obj in self) {
        if (block(obj))
            [filtered addObject: obj];
    }
    NSArray* result = [[filtered copy] autorelease];
    [filtered release];
    return result;
}
#endif

- (NSString*) my_compactDescription
{
    NSMutableString *desc = [NSMutableString stringWithCapacity: 100];
    [desc appendString: @"["];
    BOOL first = YES;
    for(id item in self) {
        if( first )
            first = NO;
        else
            [desc appendString: @", "];
        [desc appendString: [item my_compactDescription]];
    }
    [desc appendString: @"]"];
    return desc;
}

@end




@implementation NSSet (MYUtils)

- (NSString*) my_compactDescription
{
    return [[self allObjects] my_compactDescription];
}

+ (NSSet*) my_unionOfSet: (NSSet*)set1 andSet: (NSSet*)set2
{
    if( set1 == set2 || set2.count==0 )
        return set1;
    else if( set1.count==0 )
        return set2;
    else {
        NSMutableSet *result = [set1 mutableCopy];
        [result unionSet: set2];
        return [result autorelease];
    }
}

+ (NSSet*) my_intersectionOfSet: (NSSet*)set1 andSet: (NSSet*)set2
{
    if( set1 == set2 || set1.count==0 )
        return set1;
    else if( set2.count==0 )
        return set2;
    else {
        NSMutableSet *result = [set1 mutableCopy];
        [result intersectSet: set2];
        return [result autorelease];
    }
}

+ (NSSet*) my_differenceOfSet: (NSSet*)set1 andSet: (NSSet*)set2
{
    if( set1.count==0 || set2.count==0 )
        return set1;
    else if( set1==set2 )
        return [NSSet set];
    else {
        NSMutableSet *result = [set1 mutableCopy];
        [result minusSet: set2];
        return [result autorelease];
    }
}

@end


@implementation NSDictionary (MYUtils)

- (NSString*) my_compactDescription
{
    NSMutableString *desc = [NSMutableString stringWithCapacity: 100];
    [desc appendString: @"{"];
    BOOL first = YES;
    for(id key in [[self allKeys] sortedArrayUsingSelector: @selector(compare:)]) {
        if( first )
            first = NO;
        else
            [desc appendString: @", "];
        id value = [self objectForKey: key];
        [desc appendString: [key description]];
        [desc appendString: @"= "];
        [desc appendString: [value my_compactDescription]];
    }
    [desc appendString: @"}"];
    return desc;
}

@end


@implementation NSData (MYUtils)

- (NSString*) my_UTF8ToString {
    return [[[NSString alloc] initWithData: self encoding: NSUTF8StringEncoding] autorelease];
}

@end



#import "Test.h"

TestCase(CollectionUtils) {
    NSArray *a = $array(@"foo",@"bar",@"baz");
    //Log(@"a = %@",a);
    NSArray *aa = [NSArray arrayWithObjects: @"foo",@"bar",@"baz",nil];
    CAssertEqual(a,aa);
    
    const char *cstr = "a C string";
    id o = $object(cstr);
    //Log(@"o = %@",o);
    CAssertEqual(o,@"a C string");
    
    NSDictionary *d = $dict({@"int",    $object(1)},
                            {@"double", $object(-1.1)},
                            {@"char",   $object('x')},
                            {@"ulong",  $object(1234567UL)},
                            {@"longlong",$object(987654321LL)},
                            {@"cstr",   $object(cstr)});
    //Log(@"d = %@",d);
    NSDictionary *dd = [NSDictionary dictionaryWithObjectsAndKeys:
                        [NSNumber numberWithInt: 1],                    @"int",
                        [NSNumber numberWithDouble: -1.1],              @"double",
                        [NSNumber numberWithChar: 'x'],                 @"char",
                        [NSNumber numberWithUnsignedLong: 1234567UL],   @"ulong",
                        [NSNumber numberWithDouble: 987654321LL],       @"longlong",
                        @"a C string",                                  @"cstr",
                        nil];
    CAssertEqual(d,dd);
}


/*
 Copyright (c) 2008, Jens Alfke <jens@mooseyard.com>. All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification, are permitted
 provided that the following conditions are met:
 
 * Redistributions of source code must retain the above copyright notice, this list of conditions
 and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright notice, this list of conditions
 and the following disclaimer in the documentation and/or other materials provided with the
 distribution.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR
 IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND 
 FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRI-
 BUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR 
  PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN 
 CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF 
 THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */
