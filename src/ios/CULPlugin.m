//
//  CULPlugin.m
//
//  Created by Nikolay Demyankov on 14.09.15.
//

#import "CULPlugin.h"
#import "CULConfigXmlParser.h"
#import "CULPath.h"
#import "CULHost.h"
#import "CDVPluginResult+CULPlugin.h"
#import "CDVInvokedUrlCommand+CULPlugin.h"
#import "CULConfigJsonParser.h"

@interface CULPlugin() {
    NSArray *_supportedHosts;
    CDVPluginResult *_storedEvent;
    NSMutableDictionary<NSString *, NSString *> *_subscribers;
}

@end

@implementation CULPlugin

#pragma mark Public API

- (void)pluginInitialize {
    [self localInit];
    // Can be used for testing.
    // Just uncomment, close the app and reopen it. That will simulate application launch from the link.
    //[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onResume:) name:UIApplicationWillEnterForegroundNotification object:nil];
}

//- (void)onResume:(NSNotification *)notification {
//    NSUserActivity *activity = [[NSUserActivity alloc] initWithActivityType:NSUserActivityTypeBrowsingWeb];
//    [activity setWebpageURL:[NSURL URLWithString:@"http://site2.com/news/page?q=1&v=2#myhash"]];
    
//    [self handleUserActivity:activity];
//}

- (void)handleOpenURL:(NSNotification*)notification {

    id url = notification.object;
    NSLog(@"[CULPlugin] started handleOpenUrl %@ ", url);
    if (![url isKindOfClass:[NSURL class]]) {
        NSLog(@"[CULPlugin] returned early");
        return;
    }

    NSLog(@"[CULPlugin] on handleOpenUrls %@ ", url);

    CULHost *host = [self findHostByURL:url];
    if (host) {
        NSLog(@"[CULPlugin] isHost %@", url);
        [self storeEventWithHost:host originalURL:url];
    }
}

- (BOOL)handleUserActivity:(NSUserActivity *)userActivity {
    [self localInit];
    
    
    NSURL *launchURL = userActivity.webpageURL;
    CULHost *host = [self findHostByURL:launchURL];
    if (host == nil) {
        NSLog(@"[CULPlugin] handleUserActivity returned NO ");
        return NO;
    }
    
    [self storeEventWithHost:host originalURL:launchURL];
    
    return YES;
}

- (void)onAppTerminate {
    _supportedHosts = nil;
    _subscribers = nil;
    _storedEvent = nil;
    
    [super onAppTerminate];
}

#pragma mark Private API

- (void)localInit {
    if (_supportedHosts) {
        return;
    }
    
    _subscribers = [[NSMutableDictionary alloc] init];
    
    // Get supported hosts from the config.xml or www/ul.json.
    // For now priority goes to json config.
    _supportedHosts = [self getSupportedHostsFromPreferences];
}

- (NSArray<CULHost *> *)getSupportedHostsFromPreferences {
    NSString *jsonConfigPath = [[NSBundle mainBundle] pathForResource:@"ul" ofType:@"json" inDirectory:@"www"];
    if (jsonConfigPath) {
        NSLog(@"[CULPlugin] getSupportedHostsFromPreferences returns on jsonConfigPath");
        return [CULConfigJsonParser parseConfig:jsonConfigPath];
    }
    
    return [CULConfigXmlParser parse];
}

/**
 *  Store event data for future use.
 *  If we are resuming the app - try to consume it.
 *
 *  @param host        host that matches the launch url
 *  @param originalUrl launch url
 */
- (void)storeEventWithHost:(CULHost *)host originalURL:(NSURL *)originalUrl {
    NSLog(@"[CULPlugin] storeEventWithHost got %@", originalUrl.absoluteString);
    _storedEvent = [CDVPluginResult resultWithHost:host originalURL:originalUrl];
    [self tryToConsumeEvent];
}

/**
 *  Find host entry that corresponds to launch url.
 *
 *  @param  launchURL url that launched the app
 *  @return host entry; <code>nil</code> if none is found
 */
- (CULHost *)findHostByURL:(NSURL *)launchURL {
    NSLog(@"[CULPlugin] launchURL is %@", launchURL.absoluteString);

    NSURLComponents *urlComponents = [NSURLComponents componentsWithURL:launchURL resolvingAgainstBaseURL:YES];
    NSLog(@"[CULPlugin] launchURL host name is %@", urlComponents.host);

    CULHost *host = nil;
    for (CULHost *supportedHost in _supportedHosts) {
        NSLog(@"[CULPlugin] findHostByURL got %@", supportedHost.name);

        NSPredicate *pred = [NSPredicate predicateWithFormat:@"self LIKE[c] %@", supportedHost.name];
        if ([pred evaluateWithObject:urlComponents.host]) {
            NSLog(@"[CULPlugin] host is supported ");

            host = supportedHost;
            break;
        }
    }
    
    return host;
}

#pragma mark Methods to send data to JavaScript

/**
 *  Try to send event to the web page.
 *  If there is a subscriber for the event - it will be consumed. 
 *  If not - it will stay until someone subscribes to it.
 */
- (void)tryToConsumeEvent {
    if (_subscribers.count == 0 || _storedEvent == nil) {
        NSLog(@"[CULPlugin] tryToConsumeEvent returned early");
        return;
    }
    
    NSString *storedEventName = [_storedEvent eventName];
    NSLog(@"[CULPlugin] storedEventName is %@", storedEventName);
    for (NSString *eventName in _subscribers) {
        NSLog(@"[CULPlugin] iterating over eventName %@", eventName);
        if ([storedEventName isEqualToString:eventName]) {
            NSLog(@"[CULPlugin] eventName isEqualToString ");
            NSString *callbackID = _subscribers[eventName];
            [self.commandDelegate sendPluginResult:_storedEvent callbackId:callbackID];
            _storedEvent = nil;
            break;
        }
    }
}

#pragma mark Methods, available from JavaScript side

- (void)jsSubscribeForEvent:(CDVInvokedUrlCommand *)command {
    NSString *eventName = [command eventName];
    
    NSLog(@"[CULPlugin] jsSubscribeForEvent subscribed eventName %@", eventName);

    if (eventName.length == 0) {
        NSLog(@"[CULPlugin] jsSubscribeForEvent returned early");
        return;
    }
    
    _subscribers[eventName] = command.callbackId;
    [self tryToConsumeEvent];
}

- (void)jsUnsubscribeFromEvent:(CDVInvokedUrlCommand *)command {
    NSString *eventName = [command eventName];
    NSLog(@"[CULPlugin] jsUnsubscribeFromEvent eventName %@", eventName);
    if (eventName.length == 0) {
        NSLog(@"[CULPlugin] jsUnsubscribeFromEvent returned early");
        return;
    }
    
    [_subscribers removeObjectForKey:eventName];
}



@end
