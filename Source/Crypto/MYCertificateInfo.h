//
//  MYCertificateInfo.h
//  MYCrypto
//
//  Created by Jens Alfke on 6/2/09.
//  Copyright 2009 Jens Alfke. All rights reserved.
//

// ****** NOTE: Some code deleted to make this build in TouchDB! ******

#import <Foundation/Foundation.h>
@class MYCertificateName, MYOID;

/** A parsed X.509 certificate; provides access to the names and metadata. */
@interface MYCertificateInfo : NSObject 
{
    @private
    NSArray *_root;
    NSArray *_extensions;
    NSData *_data;
}

/** Initialize by parsing X.509 certificate data.
    (More commonly you'll get an instance via MYCertificate's 'info' property.) */
- (id) initWithCertificateData: (NSData*)data error: (NSError**)outError;

/** The date/time at which the certificate first becomes valid. */
@property (retain, readonly) NSDate *validFrom;

/** The date/time at which the certificate expires. */
@property (retain, readonly) NSDate *validTo;

/** Information about the identity of the owner of this certificate. */
@property (readonly) MYCertificateName *subject;

/** Information about the identity that signed/authorized this certificate. */
@property (readonly) MYCertificateName *issuer;

/** Returns YES if the issuer is the same as the subject. (Aka a "self-signed" certificate.) */
@property (readonly) BOOL isRoot;


/** The list of raw extension names, each a MYOID object. */
@property (readonly) NSArray* extensionOIDs;

/** Looks up an extension by name.
    @param oid  The extension's name.
    @param outIsCritical  On return, the BOOL variable this points to is set to YES if the extension is marked critical, else NO.
    @return  The parsed ASN.1 value, or nil if the extension is not present. This could be an NSValue or NSString, or any of the classes defined in MYASN1Object.h. */
- (id) extensionForOID: (MYOID*)oid isCritical: (BOOL*)outIsCritical;

/** Is this certificate authorized to sign certificates (i.e. serve as an issuer)?
    Returns YES if the BasicConstraints extension is present and its "cA" flag is true. */
@property (readonly) BOOL isCertificateAuthority;

/** A convenience that returns the standard KeyUsage extension value.
    @return  A combination of the kKeyUsage flags defined in this header; or kKeyUsageUnspecified if the extension is not present. (Note that this means the absence of this extension implies any key usage is valid!) */
@property (readonly) UInt16 keyUsage;

/** Checks whether the given key usage(s) are allowed by the certificate signer.
    Returns NO if the KeyUsage extension is present, and marked critical, and does not include
    all of the requested usages.
    @param keyUsage  One or more kKeyUsage flags, OR'ed together. */
- (BOOL) allowsKeyUsage: (UInt16)keyUsage;

/** A convenience that returns the standard ExtendedKeyUsage extension value, as a set of MYOIDs.
    @return  A set containing zero or more of the kExtendedKeyUsage contstants defined in this header, or nil if the extension is not present. */
@property (readonly, copy) NSSet* extendedKeyUsage;

/** Checks whether the given extended key usage(s) are allowed by the certificate signer.
    Returns NO if the ExtendedKeyUsage extension is present, and marked critical,
    and does not include all of the requested usages.
    @param extendedKeyUsage  A set of kExtendedKeyUsage OIDs. */
- (BOOL) allowsExtendedKeyUsage: (NSSet*) extendedKeyUsage;

/** The standard SubjectAlternativeName extension value parsed into an NSDictionary.
    The keys are the name types, including the strings "RFC822", "URI" and "DNS"; other name types are represented by NSNumbers whose value are the type's ASN.1 tag value.
    The dictionary values are parsed strings for the known types, and MYASN1Objects for the others. */
@property (readonly) NSDictionary* subjectAlternativeName;

/** All email addresses for the subject of this cert, including the one in the subject structure
    and the ones in the SubjectAlternativeName. */
@property (readonly) NSArray* emailAddresses;

@end



/** An X.509 Name structure, describing the subject or issuer of a certificate.
    The properties are settable only if this instance belongs to a MYCertificateRequest;
    otherwise trying to set them will raise an exception. */
@interface MYCertificateName : NSObject
{
    @private
    NSArray *_components;
}

/** The "common name" (nickname, whatever). */
@property (copy) NSString *commonName;

/** The given/first name. */
@property (copy) NSString *givenName;

/** The surname / last name / family name. */
@property (copy) NSString *surname;

/** A description. */
@property (copy) NSString *nameDescription;

/** The raw email address. */
@property (copy) NSString *emailAddress;

/** Lower-level accessor that returns the value associated with the given OID. */
- (NSString*) stringForOID: (MYOID*)oid;

/** Lower-level accessor that sets the value associated with the given OID. */
- (void) setString: (NSString*)value forOID: (MYOID*)oid;

@end



/** OIDs for KeyUsage and ExtendedKeyUsage extensions */
extern MYOID *kKeyUsageOID, *kExtendedKeyUsageOID;

/** These are the flag bits in the standard KeyUsage extension value. */
enum {
    kKeyUsageDigitalSignature   = 0x80,
    kKeyUsageNonRepudiation     = 0x40,
    kKeyUsageKeyEncipherment    = 0x20,
    kKeyUsageDataEncipherment   = 0x10,
    kKeyUsageKeyAgreement       = 0x08,
    kKeyUsageKeyCertSign        = 0x04,
    kKeyUsageCRLSign            = 0x02,
    kKeyUsageEncipherOnly       = 0x01,
    kKeyUsageDecipherOnly       = 0x100,
    kKeyUsageUnspecified        = 0xFFFF        // Returned if key-usage extension is not present
};

/** These are the constants that can appear in the extendedKeyUsage set. */
extern MYOID *kExtendedKeyUsageServerAuthOID, *kExtendedKeyUsageClientAuthOID,
             *kExtendedKeyUsageCodeSigningOID, *kExtendedKeyUsageEmailProtectionOID;
