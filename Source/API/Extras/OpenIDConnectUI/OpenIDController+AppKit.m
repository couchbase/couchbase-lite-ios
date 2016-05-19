//
//  OpenIDController+AppKit.m
//  Couchbase Lite
//
//  Created by Jens Alfke on 1/9/13.
//  Copyright (c) 2013 Couchbase. All rights reserved.
//

#import "OpenIDController+AppKit.h"
#import <WebKit/WebKit.h>


@interface OpenIDNSViewController : NSViewController <NSWindowDelegate, WebPolicyDelegate>
{
    __weak OpenIDController* _controller;
    NSPanel* _panel;
}
- (id) initWithController: (OpenIDController*)controller;
@property (readonly) WebView* webView;
@property (readonly) NSPanel* panel;
@end




@implementation OpenIDController (AppKit)

- (NSViewController*) viewController {
    if (!_UIController) {
        _UIController = [[OpenIDNSViewController alloc] initWithController: self];
    }
    return _UIController;
}

- (NSPanel*) panel {
    return [(OpenIDNSViewController*)self.viewController panel];
}

- (void) presentUI {
    _presentedUI = self.panel;
    [(NSPanel*)_presentedUI makeKeyAndOrderFront: self];
}

- (void) closeUI {
    [(NSPanel*)_presentedUI close];
    _presentedUI = nil;
}

@end




@implementation OpenIDNSViewController

@synthesize webView=_webView;

- (id) initWithController: (OpenIDController*)controller {
    self = [super init];
    if (self) {
        _controller = controller;
    }
    return self;
}

- (void) loadView {
    _webView = [[WebView alloc] initWithFrame: NSMakeRect(0, 0, 500, 400)];
    _webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _webView.policyDelegate = self;
    self.view = _webView;

    [_webView.mainFrame loadRequest: [NSURLRequest requestWithURL: _controller.loginURL]];
}

- (NSPanel*)panel {
    if (!_panel) {
        _panel = [[NSPanel alloc] initWithContentRect: NSMakeRect(0, 0, 500, 450)
                                            styleMask: NSTitledWindowMask | NSClosableWindowMask | NSResizableWindowMask
                                              backing: NSBackingStoreBuffered
                                                defer: YES];
        NSRect frame = NSInsetRect([_panel.contentView bounds], 8, 8);
        frame.origin.y += 40;
        frame.size.height -= 40;
        self.view.frame = frame;
        [_panel.contentView addSubview: self.view];

        NSButton* cancel = [[NSButton alloc] initWithFrame: NSZeroRect];
        cancel.buttonType = NSMomentaryLightButton;
        cancel.bezelStyle = NSRoundedBezelStyle;
        cancel.title = @"Cancel";
        cancel.target = self;
        cancel.action = @selector(cancel);
        cancel.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
        [cancel sizeToFit];
        frame = cancel.frame;
        frame.origin.x = 500 - 8 - frame.size.width;
        frame.origin.y = 8;
        cancel.frame = frame;
        [_panel.contentView addSubview: cancel];
        _panel.title = [NSString stringWithFormat: @"OpenID Login: %@",
                        _controller.loginURL.host];
        [_panel center];
        _panel.delegate = self;
    }
    return _panel;
}

- (IBAction) cancel {
    [_webView.mainFrame stopLoading];
    OpenIDController* controller = _controller;
    [controller.delegate openIDControllerDidCancel: controller];
}

- (BOOL) windowShouldClose: (id)sender {
    [self cancel];
    return NO; // delegate already closed me
}

- (void) windowWillClose:(NSNotification *)notification {
    _panel = nil;
}

// WebPolicyDelegate method
- (void) webView:(WebView *)webView
         decidePolicyForNavigationAction:(NSDictionary *)actionInformation
         request:(NSURLRequest *)request
         frame:(WebFrame *)frame
         decisionListener:(id<WebPolicyDecisionListener>)listener
{
    NSURL* url = request.URL;
    OpenIDController* controller = _controller;
    if (![controller navigateToURL: url]) {
        [listener ignore];
        return;
    } else if ([[[url scheme] lowercaseString] isEqualToString: @"http"] ||
               [[[url scheme] lowercaseString] isEqualToString: @"https"])
    {
        if (![url.host isEqual: controller.loginURL.host]) {
            // Open other URLs in default web browser:
            [[NSWorkspace sharedWorkspace] openURL: url];
            [listener ignore];
            return;
        }
    }

    // default:
    [listener use];
}


@end