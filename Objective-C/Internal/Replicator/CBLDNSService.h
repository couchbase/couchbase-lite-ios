//
//  DNSResolver.h
//  TestDNSService
//
//  Created by Pasin Suriyentrakorn on 12/4/22.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, IPType) {
    kIPv4 = 0,
    kIPv6
};

@interface AddressInfo : NSObject

@property (nonatomic, readonly) const struct sockaddr* addr;
@property (nonatomic, readonly) NSString* addrstr; // For debugging or logging
@property (nonatomic, readonly) IPType type;

@end

@protocol DNSServiceDelegate <NSObject>
- (void) didResolveSuccessWithAddress: (AddressInfo*)info;
- (void) didResolveFailWithError: (NSError*)error;
@end

@interface CBLDNSResolver : NSObject

- (instancetype) initWithHost: (NSString*)host interface: (uint32_t)interface port: (UInt16)port delegate: (id<DNSServiceDelegate>)delegate;
- (void) start;
- (void) stop;

@end

NS_ASSUME_NONNULL_END
