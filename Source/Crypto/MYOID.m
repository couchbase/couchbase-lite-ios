//
//  MYOID.m
//  MYCrypto
//
//  Created by Jens Alfke on 5/28/09.
//  Copyright 2009 Jens Alfke. All rights reserved.
//

#import "MYOID.h"


@implementation MYOID


- (id) initWithComponents: (const UInt32*)components count: (unsigned)count
{
    self = [super init];
    if (self != nil) {
        _data = [[NSData alloc] initWithBytes: components length: count*sizeof(UInt32)];
    }
    return self;
}

- (id) initWithBEREncoding: (NSData*)encoding
{
    self = [super init];
    if (self != nil) {
        size_t len = encoding.length;
        const UInt8 *src = encoding.bytes;
        const UInt8 *end = src+len;
        NSMutableData *data = [NSMutableData dataWithLength: (len+1)*sizeof(UInt32)];
        UInt32* dst = data.mutableBytes;
        
        if (len >= 2) {
            *dst++ = *src / 40;
            *dst++ = *src % 40;
            src++; 
        }
        while (src < end) {
            UInt32 component = 0;
            UInt8 byte;
            do{
                if (src >= end) {
                    [self release];
                    return nil;
                }
                byte = *src++;
                component = (component << 7) | (byte & 0x7F);
            }while (byte & 0x80);
            *dst++ = component;
        }
        data.length = (UInt8*)dst - (UInt8*)data.mutableBytes;
        _data = [data copy];
    }
    return self;
}

+ (MYOID*) OIDWithEncoding: (NSData*)encoding {
    return [[[self alloc] initWithBEREncoding: encoding] autorelease];
}

#if !TARGET_OS_IPHONE
+ (MYOID*) OIDFromCSSM: (CSSM_OID)cssmOid
{
    NSData *ber = [[NSData alloc] initWithBytesNoCopy: cssmOid.Data length: cssmOid.Length freeWhenDone: NO];
    MYOID *oid = [[[self alloc] initWithBEREncoding: ber] autorelease];
    [ber release];
    return oid;
}
#endif


- (id) copyWithZone: (NSZone*)zone {
    return [self retain];
}

- (void) dealloc
{
    [_data release];
    [super dealloc];
}


- (NSString*) description {
    NSMutableString *desc = [NSMutableString stringWithString: @"{"];
    const UInt32* components = self.components;
    unsigned count = self.componentCount;
    for (unsigned i=0; i<count; i++) {
        if (i>0)
            [desc appendString: @" "];
        [desc appendFormat: @"%u", components[i]];
    }
    [desc appendString: @"}"];
    return desc;
}


- (NSData*) componentData       {return _data;}
- (const UInt32*) components    {return (const UInt32*)_data.bytes;}
- (unsigned) componentCount     {return (unsigned)(_data.length / sizeof(UInt32));}

- (NSUInteger)hash {
    return _data.hash;
}

- (BOOL)isEqual:(id)object {
    return [object isKindOfClass: [MYOID class]] && [_data isEqual: [object componentData]];
}


- (NSData*) DEREncoding {
    unsigned count = self.componentCount;
    UInt8 encoding[5*count]; // worst-case size
    const UInt32 *src=self.components, *end=src+count;
    UInt8 *dst = encoding;
    if (count >= 2 && src[0]<=3 && src[1]<40) {
        // Weird collapsing of 1st two components into one byte:
        *dst++ = (UInt8)(src[0]*40 + src[1]);
        src += 2;
    }
    while (src<end) {
        UInt32 component = *src++;
        // Write the component in 7-bit groups, most significant first:
        BOOL any = NO;
        for (int shift=28; shift>=0; shift -= 7) {
            UInt8 byte = (component >> shift) & 0x7F;
            if (byte || any) {
                if (any)
                    dst[-1] |= 0x80;
                *dst++ = byte;
                any = YES;
            }
        }
    }
    return [NSData dataWithBytes: encoding length: dst-encoding];
}


@end



#define $data(BYTES...)    ({const uint8_t bytes[] = {BYTES}; [NSData dataWithBytes: bytes length: sizeof(bytes)];})

#define $components(INTS...)    ({const UInt32 components[] = {INTS}; components;})

TestCase(OID) {
    CAssertEqual([[MYOID OIDWithEncoding: $data(0x2a,0x86,0x48,0x86,0xf7,0x0d,0x01,0x01,0x01)] description],
                 @"{1 2 840 113549 1 1 1}");
    CAssertEqual([[MYOID OIDWithEncoding: $data(0x55,0x04,0x04)] description],
                 @"{2 5 4 4}");
    CAssertEqual([[MYOID OIDWithEncoding: $data(0x2a,0x86,0x48,0x86,0xf7,0x0d,0x01,0x09,0x01)] description],
                 @"{1 2 840 113549 1 9 1}");

    CAssertEqual([[[MYOID alloc] initWithComponents: $components(1,2,840,113549,1,1,1) count: 7] description],
                 @"{1 2 840 113549 1 1 1}");

    CAssertEqual([[[MYOID alloc] initWithComponents: $components(1,2,840,113549,1,1,1) count: 7] DEREncoding],
                 $data(0x2a, 0x86, 0x48, 0x86,  0xf7, 0x0d, 0x01, 0x01,  0x01));
    CAssertEqual([[[MYOID alloc] initWithComponents: $components(2,5,4,4) count: 4] DEREncoding],
                 $data(0x55,0x04,0x04));
}



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
