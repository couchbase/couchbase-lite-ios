//
//  MYBERParser.m
//  MYCrypto
//
//  Created by Jens Alfke on 6/2/09.
//  Copyright 2009 Jens Alfke. All rights reserved.
//

// Reference:
// <http://luca.ntop.org/Teaching/Appunti/asn1.html> "Layman's Guide To ASN.1/BER/DER"

#import "MYBERParser.h"
#import "MYASN1Object.h"
#import "MYOID.h"
#import "MYErrorUtils.h"
#import "CollectionUtils.h"
#import "Test.h"


#define MYBERParserException @"MYBERParserException"



typedef struct {
    unsigned tag            :5;
    unsigned isConstructed  :1;
    unsigned tagClass       :2;
    unsigned length         :7;
    unsigned isLengthLong   :1;
} BERHeader;

typedef struct {
    const uint8_t *nextChar;
    size_t length;
} InputData;


static void requireLength (size_t length, size_t expectedLength) {
    if (length != expectedLength)
        [NSException raise: MYBERParserException format: @"Unexpected value length"];
}


static const void* readOrDie (InputData *input, size_t len) {
    if (len > input->length)
        [NSException raise: MYBERParserException format: @"Unexpected EOF on input"];
    const void *bytes = input->nextChar;
    input->nextChar += len;
    input->length -= len;
    return bytes;
}


static NSData* readDataOrDie(InputData *input, size_t length) {
    return [NSMutableData dataWithBytes: readOrDie(input,length) length: length];
}


static NSString* readStringOrDie(InputData *input, size_t length, NSStringEncoding encoding) {
    NSString *str = [[NSString alloc] initWithBytes: readOrDie(input,length) 
                                             length: length
                                           encoding: encoding];
    if (!str)
        [NSException raise: MYBERParserException format: @"Unparseable string"];
    return [str autorelease];
}    


static uint32_t readBigEndianUnsignedInteger (InputData *input, size_t length) {
    if (length == 0 || length > 4)
        [NSException raise: MYBERParserException format: @"Invalid integer length"];
    uint32_t result = 0;
    memcpy(((uint8_t*)&result)+(4-length), readOrDie(input, length), length);
    return result;
}

static int32_t readBigEndianSignedInteger (InputData *input, size_t length) {
    int32_t result = (int32_t) readBigEndianUnsignedInteger(input,length);
    uint8_t *dst = ((uint8_t*)&result)+(4-length);
    if (*dst & 0x80) { // sign-extend negative value
        while (--dst >= (uint8_t*)&result)
            *dst = 0xFF;
    }
    return result;
}


NSDateFormatter* MYBERGeneralizedTimeFormatter(void) {
    static NSDateFormatter *sFmt;
    if (!sFmt) {
        sFmt = [[NSDateFormatter alloc] init];
        sFmt.dateFormat = @"yyyyMMddHHmmss'Z'";
        sFmt.timeZone = [NSTimeZone timeZoneWithName: @"GMT"];
    }
    return sFmt;
}

NSDateFormatter* MYBERUTCTimeFormatter(void) {
    static NSDateFormatter *sFmt;
    if (!sFmt) {
        sFmt = [[NSDateFormatter alloc] init];
        sFmt.dateFormat = @"yyMMddHHmmss'Z'";
        sFmt.timeZone = [NSTimeZone timeZoneWithName: @"GMT"];
    }
    return sFmt;
}

static NSDate* parseDate (NSString *dateStr, unsigned tag) {
    //FIX: There are more date formats possible; need to try them all. (see "Layman's Guide", 5.17)
    NSDateFormatter *fmt = (tag==23 ?MYBERUTCTimeFormatter() :MYBERGeneralizedTimeFormatter());
    NSDate *date = [fmt dateFromString: dateStr];
    if (!date)
        [NSException raise: MYBERParserException format: @"Unparseable date '%@'", dateStr];
    return date;
}


static size_t readHeader(InputData *input, BERHeader *header) {
    memcpy(header, readOrDie(input,2), 2);
    if (header->tag == 0x1F)
        [NSException raise: MYBERParserException format: @"Long tags not supported"];
    if (!header->isLengthLong)
        return header->length;
    else {
        if (header->length == 0)
            [NSException raise: MYBERParserException format: @"Indefinite length not supported"];
        return NSSwapBigIntToHost(readBigEndianUnsignedInteger(input,header->length));
    }
}


static id parseBER(InputData *input) {
    BERHeader header;
    size_t length = readHeader(input,&header);
    
    Class defaultClass = [MYASN1Object class];
    
    // Tag values can be found in <Security/x509defs.h>. I'm not using them here because that
    // header does not exist on iPhone!
    
    if (header.isConstructed) {
        // Constructed:
        NSMutableArray *items = $marray();
        InputData subInput = {input->nextChar, length};
        while (subInput.length > 0) {
            [items addObject: parseBER(&subInput)];
        }
        input->nextChar += length;
        input->length -= length;

        if (header.tagClass == 0) {
            switch (header.tag) {
                case 16: // sequence
                    return items;
                case 17: // set
                    return [NSSet setWithArray: items];
                default:
                    Warn(@"MYBERParser: Unrecognized constructed tag %u", header.tag);
                    break;
            }
        }
        return [[[MYASN1Object alloc] initWithTag: header.tag
                                          ofClass: header.tagClass
                                       components: items] autorelease];

    } else if (header.tagClass == 0) {
        // Primitive:
        switch (header.tag) {
            case 1: { // boolean
                requireLength(length,1);
                return *(const uint8_t*)readOrDie(input, 1) ?$true :$false;
            }
            case 2: // integer
            case 10: // enum
            {
                if (length <= 4) {
                    int32_t value = NSSwapBigIntToHost(readBigEndianSignedInteger(input,length));
                    return [NSNumber numberWithInteger: value];
                } else {
                    // Big integer!
                    defaultClass = [MYASN1BigInteger class];
                    break;
                }
            }
            case 3: // bitstring
            {
                UInt8 unusedBits = *(const UInt8*) readOrDie(input, 1);
                if (unusedBits > 7 || length < 1)
                    [NSException raise: MYBERParserException format: @"Bogus bit-string"];
                return [[[MYBitString alloc] initWithBits: readDataOrDie(input, length-1)
                                                    count: 8*(length-1) - unusedBits] autorelease];
            }
            case 4: // octetstring
                return readDataOrDie(input, length);
            case 5: // null
                requireLength(length,0);
                return [NSNull null];
            case 6: // OID
                return [[[MYOID alloc] initWithBEREncoding: readDataOrDie(input, length)] autorelease];
            case 12: // UTF8String
                return readStringOrDie(input,length,NSUTF8StringEncoding);
            case 18: // numeric string
            case 19: // printable string:
            case 22: // IA5 string:
            case 20: // T61 string:
            {
                NSString *string = readStringOrDie(input,length,NSASCIIStringEncoding);
                if (string)
                    return string;
                else
                    break;  // if decoding fails, fall back to generic MYASN1Object
            }
            case 23: // UTC time:
            case 24: // Generalized time:
                return parseDate(readStringOrDie(input,length,NSASCIIStringEncoding), header.tag);
            default:
                Warn(@"MYBERParser: Unrecognized primitive tag %u", header.tag);
                break;
        }
    }
    
    // Generic case -- create and return a MYASN1Object:
    NSData *value = readDataOrDie(input, length);
    return [[[defaultClass alloc] initWithTag: header.tag
                                      ofClass: header.tagClass 
                                  constructed: header.isConstructed
                                        value: value] autorelease];
}
    
    
static BOOL exceptionToError (NSException *x, NSError **outError) {
    if ($equal(x.name, MYBERParserException)) {
        if (outError)
            *outError = MYError(1,MYASN1ErrorDomain, @"%@", x.reason);
    } else {
        @throw(x);
    }
    return NO;  // not used by caller, but appeases the static analyzer
}


id MYBERParse (NSData *ber, NSError **outError) {
    CAssert(ber);
    @try{
        InputData input = {ber.bytes, ber.length};
        return parseBER(&input);
    }@catch (NSException *x) {
        exceptionToError(x,outError);
    }
    return nil;
}


size_t MYBERGetLength (NSData *ber, NSError **outError) {
    CAssert(ber);
    @try{
        InputData input = {ber.bytes, ber.length};
        BERHeader header;
        return readHeader(&input,&header);
    }@catch (NSException *x) {
        exceptionToError(x,outError);
    }
    return 0;
}

const void* MYBERGetContents (NSData *ber, NSError **outError) {
    @try{
        InputData input = {ber.bytes, ber.length};
        BERHeader header;
        readHeader(&input,&header);
        return input.nextChar;
    }@catch (NSException *x) {
        exceptionToError(x,outError);
    }
    return NULL;
}



#pragma mark -
#pragma mark TEST CASES:


#define $data(BYTES...)    ({const uint8_t bytes[] = {BYTES}; [NSData dataWithBytes: bytes length: sizeof(bytes)];})

TestCase(ParseBER) {
    CAssertEqual(MYBERParse($data(0x05, 0x00), nil),
                 [NSNull null]);
    CAssertEqual(MYBERParse($data(0x01, 0x01, 0xFF), nil),
                 $true);
    CAssertEqual(MYBERParse($data(0x01, 0x01, 0x00), nil),
                 $false);
    
    // integers:
    CAssertEqual(MYBERParse($data(0x02, 0x01, 0x00), nil),
                 $object(0));
    CAssertEqual(MYBERParse($data(0x02, 0x01, 0x48), nil),
                 $object(72));
    CAssertEqual(MYBERParse($data(0x02, 0x01, 0x80), nil),
                 $object(-128));
    CAssertEqual(MYBERParse($data(0x02, 0x02, 0x00, 0x80), nil),
                 $object(128));
    CAssertEqual(MYBERParse($data(0x02, 0x02, 0x30,0x39), nil),
                 $object(12345));
    CAssertEqual(MYBERParse($data(0x02, 0x02, 0xCF, 0xC7), nil),
                 $object(-12345));
    CAssertEqual(MYBERParse($data(0x02, 0x04, 0x07, 0x5B, 0xCD, 0x15), nil),
                 $object(123456789));
    CAssertEqual(MYBERParse($data(0x02, 0x04, 0xF8, 0xA4, 0x32, 0xEB), nil),
                 $object(-123456789));
    CAssertEqual(MYBERParse($data(0x02, 0x04, 0xF8, 0xA4, 0x32, 0xEB), nil),
                 $object(-123456789));
    
    // octet strings:
    CAssertEqual(MYBERParse($data(0x04, 0x05, 'h', 'e', 'l', 'l', 'o'), nil),
                 [@"hello" dataUsingEncoding: NSASCIIStringEncoding]);
    CAssertEqual(MYBERParse($data(0x04, 0x00), nil),
                 [NSData data]);
    CAssertEqual(MYBERParse($data(0x0C, 0x05, 'h', 'e', 'l', 'l', 'o'), nil),
                 @"hello");
    
    // sequences:
    CAssertEqual(MYBERParse($data(0x30, 0x06,  0x02, 0x01, 0x48,  0x01, 0x01, 0xFF), nil),
                 $array($object(72), $true));
    CAssertEqual(MYBERParse($data(0x30, 0x10,  
                                  0x30, 0x06,  0x02, 0x01, 0x48,  0x01, 0x01, 0xFF,
                                  0x30, 0x06,  0x02, 0x01, 0x48,  0x01, 0x01, 0xFF), nil),
                 $array( $array($object(72), $true), $array($object(72), $true)));
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
