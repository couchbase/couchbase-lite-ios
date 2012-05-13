//
//  MYASN1Object.h
//  MYCrypto
//
//  Created by Jens Alfke on 5/28/09.
//  Copyright 2009 Jens Alfke. All rights reserved.
//

#import <Foundation/Foundation.h>


/* A generic ASN.1 data value. The BER parser instantiates these to represent parsed values that
    it doesn't know how to represent otherwise.
    This is mostly used internally by MYParsedCertificate. */
@interface MYASN1Object : NSObject
{
    @private
    uint32_t _tag;
    uint8_t _tagClass;
    BOOL _constructed;
    NSData *_value;
    NSArray *_components;
}

- (id) initWithTag: (uint32_t)tag
           ofClass: (uint8_t)tagClass 
       constructed: (BOOL)constructed
             value: (NSData*)value;
- (id) initWithTag: (uint32_t)tag
           ofClass: (uint8_t)tagClass 
        components: (NSArray*)components;

@property (readonly) uint32_t tag;
@property (readonly) uint8_t tagClass;
@property (readonly) BOOL constructed;
@property (readonly) NSData *value;
@property (readonly) NSString *ASCIIValue;
@property (readonly) NSArray *components;

+ (NSString*) dump: (id)object;

@end


/* An ASN.1 "big" (arbitrary-length) integer.
    The value contains the bytes of the integer, in big-endian order.
    This is mostly used internally by MYParsedCertificate. */
@interface MYASN1BigInteger : MYASN1Object
- (id) initWithSignedData: (NSData*)signedData;
- (id) initWithUnsignedData: (NSData*) unsignedData;
@property (readonly) NSData *signedData, *unsignedData;
@end


/* An ordered string of bits, as used in ASN.1.
    This differs from NSData in that it need not occupy a whole number of bytes;
    that is, the number of bits need not be a multiple of 8.
    This is mostly used internally by MYParsedCertificate. */
@interface MYBitString : NSObject 
{
    @private
    NSData *_bits;
    NSUInteger _bitCount;
}

- (id)initWithBits: (NSData*)bits count: (NSUInteger)bitCount;
+ (MYBitString*) bitStringWithData: (NSData*)bits;

@property (readonly, nonatomic) NSData *bits;
@property (readonly, nonatomic) NSUInteger bitCount;

@end
