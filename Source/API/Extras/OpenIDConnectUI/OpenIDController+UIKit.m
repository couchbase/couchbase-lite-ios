//
//  OpenIDController+UIKit.m
//  Couchbase Lite
//
//  Created by Jens Alfke on 1/9/13.
//  Copyright (c) 2013 Couchbase. All rights reserved.
//

#import "OpenIDController+UIKit.h"
@import WebKit;


@interface OpenIDUIViewController : UIViewController <WKNavigationDelegate>
{
    OpenIDController* _controller;
    WKWebView* _webView;
}
- (id) initWithController: (OpenIDController*)controller;
@end


@implementation OpenIDController (UIKit)


- (UIViewController*) viewController {
    if (!_UIController) {
        _UIController = [[OpenIDUIViewController alloc] initWithController: self];
    }
    return _UIController;
}

/** A convenience method that puts the receiver in a UINavigationController and presents it modally
 in the given parent controller. */
- (UINavigationController*) presentModalInController: (UIViewController*)parentController {
    NSParameterAssert(parentController);
    UIViewController* viewController = self.viewController;
    if (!viewController)
        return nil;
    UINavigationController* navController = [[UINavigationController alloc]
                                             initWithRootViewController: viewController];
    if (navController == nil)
        return nil;

    if (UI_USER_INTERFACE_IDIOM() != UIUserInterfaceIdiomPhone) {
        navController.modalPresentationStyle = UIModalPresentationFormSheet;
    }
    [parentController presentViewController: navController animated: YES completion: nil];
    return navController;
}

- (void) presentUI {
    UIViewController* parent = [UIApplication sharedApplication].keyWindow.rootViewController;
    _presentedUI = [self presentModalInController: parent];
}

- (void) closeUI {
    [(OpenIDUIViewController*)_presentedUI dismissViewControllerAnimated: YES completion:^{
        _presentedUI = nil;
    }];
}

@end


@implementation OpenIDUIViewController

- (id) initWithController: (OpenIDController*)controller {
    self = [super init];
    if (self) {
        _controller = controller;
    }
    return self;
}

- (void) loadView {
    UIView* rootView = [[UIView alloc] initWithFrame: CGRectMake(0, 0, 200, 200)];
    _webView = [[WKWebView alloc] initWithFrame: rootView.bounds];
    _webView.navigationDelegate = self;
    _webView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    [rootView addSubview: _webView];

    self.view = rootView;
}

- (void) viewDidLoad {
    [super viewDidLoad];

    self.title = NSLocalizedString(@"Log In With OpenID", @"OpenID login window title");

    UIBarButtonItem* cancelButton = [[UIBarButtonItem alloc] initWithTitle: @"Cancel"
                                                                     style: UIBarButtonItemStylePlain target: self action: @selector(cancel)];
    self.navigationItem.rightBarButtonItem = cancelButton;
}

- (void) viewWillAppear:(BOOL)animated {
    [super viewWillAppear: animated];
    [_webView loadRequest: [NSURLRequest requestWithURL: _controller.loginURL]];
}

- (IBAction) cancel {
    [_webView stopLoading];
    [_controller.delegate openIDControllerDidCancel: _controller];
}

- (void)webView:(WKWebView *)webView
        decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
        decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler
{
    BOOL navigate = [_controller navigateToURL: navigationAction.request.URL];
    decisionHandler(navigate ? WKNavigationActionPolicyAllow : WKNavigationActionPolicyCancel);
}

@end
