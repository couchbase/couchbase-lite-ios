//
//  MYASN1Object.m
//  MYCrypto
//
//  Created by Jens Alfke on 5/28/09.
//  Copyright 2009 Jens Alfke. All rights reserved.
//

// Reference:
// <http://www.columbia.edu/~ariel/ssleay/layman.html> "Layman's Guide To ASN.1/BER/DER"

#import "MYASN1Object.h"


@implementation MYASN1Object


- (id) initWithTag: (uint32_t)tag
           ofClass: (uint8_t)tagClass 
       constructed: (BOOL)constructed
             value: (NSData*)value
{
    Assert(value);
    self = [super init];
    if (self != nil) {
        _tag = tag;
        _tagClass = tagClass;
        _constructed = constructed;
        _value = [value copy];
    }
    return self;
}

- (id) initWithTag: (uint32_t)tag
           ofClass: (uint8_t)tagClass 
        components: (NSArray*)components
{
    Assert(components);
    self = [super init];
    if (self != nil) {
        _tag = tag;
        _tagClass = tagClass;
        _constructed = YES;
        _components = [components copy];
    }
    return self;
}

- (void) dealloc
{
    [_value release];
    [_components release];
    [super dealloc];
}


@synthesize tag=_tag, tagClass=_tagClass, constructed=_constructed, value=_value, components=_components;


- (NSString*) ASCIIValue {
    return [[[NSString alloc] initWithData: _value encoding: NSASCIIStringEncoding] autorelease];
}

- (NSString*)description {
    if (_components)
        return $sprintf(@"%@[%hhu/%u/%u]%@", self.class, _tagClass,(unsigned)_constructed,_tag, _components);
    else
        return $sprintf(@"%@[%hhu/%u/%u, %u bytes]", self.class, _tagClass,(unsigned)_constructed,_tag, _value.length);
}

- (BOOL) isEqual: (id)object {
    return [object isKindOfClass: [MYASN1Object class]] 
        && _tag==[object tag] 
        && _tagClass==[object tagClass] 
        && _constructed==[object constructed] 
        && $equal(_value,[object value])
        && $equal(_components,[object components]);
}

static void dump(id object, NSMutableString *output, NSString *indent) {
    if ([object isKindOfClass: [MYASN1Object class]]) {
        MYASN1Object *asn1Obj = object;
        [output appendFormat: @"%@%@[%hhu/%u]", indent, asn1Obj.class, asn1Obj.tagClass,asn1Obj.tag];
        if (asn1Obj.components) {
            [output appendString: @":\n"];
            NSString *subindent = [indent stringByAppendingString: @"    "];
            for (id o in asn1Obj.components)
                dump(o,output, subindent);
        } else
            [output appendFormat: @" %@\n", asn1Obj.value];
    } else if([object respondsToSelector: @selector(objectEnumerator)]) {
        [output appendString: indent];
        if ([object isKindOfClass: [NSArray class]])
            [output appendString: @"Sequence:\n"];
        else if ([object isKindOfClass: [NSSet class]])
            [output appendString: @"Set:\n"];
        else
            [output appendFormat: @"%@:\n", [object class]];
        NSString *subindent = [indent stringByAppendingString: @"    "];
        for (id o in object)
            dump(o,output, subindent);
    } else {
        [output appendFormat: @"%@%@\n", indent, object];
    }
}

+ (NSString*) dump: (id)object {
    NSMutableString *output = [NSMutableString stringWithCapacity: 512];
    dump(object,output,@"");
    return output;
}


@end



@implementation MYASN1BigInteger

- (id) initWithSignedData: (NSData*)signedData {
    // Skip unnecessary leading 00 (if positive) or FF (if negative) bytes:
    const SInt8 *start = signedData.bytes, *last = start + signedData.length - 1;
    const SInt8 *pos = start;
    while (pos<last && ((pos[0]==0 && pos[1]>=0) || (pos[0]==-1 && pos[1]<0)))
        pos++;
    if (pos > start)
        signedData = [NSData dataWithBytes: pos length: last-pos+1];
    return [self initWithTag: 2 ofClass: 0 constructed: NO value: signedData];
}

- (id) initWithUnsignedData: (NSData*) unsignedData {
    const UInt8 *start = unsignedData.bytes;
    if (*start >= 0x80) {
        // Prefix with 00 byte so high bit isn't misinterpreted as a sign bit:
        NSMutableData *fixedData = [NSMutableData dataWithCapacity: unsignedData.length + 1];
        UInt8 zero = 0;
        [fixedData appendBytes: &zero length: 1];
        [fixedData appendData: unsignedData];
        unsignedData = fixedData;
    }
    return [self initWithSignedData: unsignedData];
}

- (NSData*) signedData {
    return self.value;
}

- (NSData*) unsignedData {
    // Strip any leading zero bytes that were inserted for sign-bit padding:
    NSData *data = self.value;
    const UInt8 *start = data.bytes, *last = start + data.length - 1;
    const UInt8 *pos = start;
    while (pos<last && *pos==0)
        pos++;
    if (pos > start)
        data = [NSData dataWithBytes: pos length: last-pos+1];
    return data;
}

@end



@implementation MYBitString


- (id)initWithBits: (NSData*)bits count: (NSUInteger)bitCount {
    Assert(bits);
    Assert(bitCount <= 8*bits.length);
    self = [super init];
    if (self != nil) {
        _bits = [bits copy];
        _bitCount = bitCount;
    }
    return self;
}

+ (MYBitString*) bitStringWithData: (NSData*)bits {
    return [[[self alloc] initWithBits: bits count: 8*bits.length] autorelease];
}

- (void) dealloc
{
    [_bits release];
    [super dealloc];
}

@synthesize bits=_bits, bitCount=_bitCount;

- (NSString*) description {
    return $sprintf(@"%@%@", [self class], _bits);
}

- (NSUInteger) hash {
    return _bits.hash ^ _bitCount;
}

- (BOOL) isEqual: (id)object {
    return [object isKindOfClass: [MYBitString class]] 
        && _bitCount==[object bitCount] 
        && [_bits isEqual: [object bits]];
}

@end



/*
 Copyright (c) 2009, Jens Alfke <jens@mooseyard.com>. All rights reserved.
 
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
