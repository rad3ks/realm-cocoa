////////////////////////////////////////////////////////////////////////////
//
// Copyright 2016 Realm Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
////////////////////////////////////////////////////////////////////////////

#import "RLMSyncSessionRefreshHandle.hpp"

#import "RLMAuthResponseModel.h"
#import "RLMNetworkClient.h"
#import "RLMSyncManager_Private.h"
#import "RLMSyncUser_Private.hpp"
#import "RLMTokenModels.h"

#import "sync/sync_session.hpp"

using namespace realm;

@interface RLMSyncSessionRefreshHandle () {
    std::weak_ptr<SyncSession> _session;
}

@property (nonatomic, weak) RLMSyncUser *user;
@property (nonatomic, strong) NSString *pathToRealm;
@property (nonatomic) NSTimer *timer;

@end

@implementation RLMSyncSessionRefreshHandle

- (instancetype)initWithPathToRealm:(NSString *)path
                               user:(RLMSyncUser *)user
                            session:(std::shared_ptr<realm::SyncSession>)session {
    if (self = [super init]) {
        self.pathToRealm = path;
        self.user = user;
        _session = std::move(session);
        return self;
    }
    return nil;
}

- (void)dealloc {
    [self.timer invalidate];
}

- (void)invalidate {
    [self.timer invalidate];
}

+ (NSDate *)fireDateForTokenExpirationDate:(NSDate *)date {
    static NSTimeInterval refreshBuffer = 10;
    NSDate *fireDate = [date dateByAddingTimeInterval:-refreshBuffer];
    // Only fire times in the future are valid.
    return ([fireDate compare:[NSDate date]] != NSOrderedDescending ? fireDate : nil);
}

- (void)scheduleRefreshTimer:(NSDate *)dateWhenTokenExpires {
    // Schedule the timer on the main queue.
    // It's very likely that this method will be run on a side thread, for example
    // on the thread that runs `NSURLSession`'s completion blocks. We can't be
    // guaranteed that there's an existing runloop on those threads, and we don't want
    // to create and start a new one if one doesn't already exist.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.timer invalidate];
        // The fire time is `self.refreshBuffer` seconds before the token expires.
        NSDate *fireDate = [RLMSyncSessionRefreshHandle fireDateForTokenExpirationDate:dateWhenTokenExpires];
        if (!fireDate) {
            [self.user _unregisterRefreshHandleForURLPath:self.pathToRealm];
            return;
        }
        NSTimer *t = [[NSTimer alloc] initWithFireDate:fireDate
                                              interval:0
                                                target:self
                                              selector:@selector(timerFired:)
                                              userInfo:nil
                                               repeats:NO];
        [[NSRunLoop currentRunLoop] addTimer:t forMode:NSDefaultRunLoopMode];
        self.timer = t;
    });
}

- (void)timerFired:(__unused NSTimer *)timer {
    RLMSyncUser *user = self.user;
    if (!user) {
        return;
    }
    RLMServerToken refreshToken = user._refreshToken;
    if (!refreshToken) {
        [user _unregisterRefreshHandleForURLPath:self.pathToRealm];
        [self.timer invalidate];
        return;
    }

    NSDictionary *json = @{
                           kRLMSyncProviderKey: @"realm",
                           kRLMSyncPathKey: self.pathToRealm,
                           kRLMSyncDataKey: refreshToken,
                           kRLMSyncAppIDKey: [RLMSyncManager sharedManager].appID,
                           };

    RLMSyncCompletionBlock handler = ^(NSError *error, NSDictionary *json) {
        if (json && !error) {
            RLMAuthResponseModel *model = [[RLMAuthResponseModel alloc] initWithDictionary:json
                                                                        requireAccessToken:YES
                                                                       requireRefreshToken:NO];
            if (!model) {
                // Malformed JSON
                error = [NSError errorWithDomain:RLMSyncErrorDomain
                                            code:RLMSyncErrorBadResponse
                                        userInfo:@{kRLMSyncErrorJSONKey: json}];
                [user _unregisterRefreshHandleForURLPath:self.pathToRealm];
                [self.timer invalidate];
                [[RLMSyncManager sharedManager] _fireError:error];
                return;
            }

            // Success
            if (auto session = _session.lock()) {
                if (session->state() != SyncSession::PublicState::Error) {
                    session->refresh_access_token([model.accessToken.token UTF8String], none);
                    NSDate *expiration = [NSDate dateWithTimeIntervalSince1970:model.accessToken.tokenData.expires];
                    [self scheduleRefreshTimer:expiration];
                    return;
                }
            }
            // The session is dead or in a fatal error state.
            [user _unregisterRefreshHandleForURLPath:self.pathToRealm];
            [self.timer invalidate];
            return;
        }

        // Something else went wrong
        NSError *syncError = [NSError errorWithDomain:RLMSyncErrorDomain
                                                 code:RLMSyncErrorBadResponse
                                             userInfo:@{kRLMSyncUnderlyingErrorKey: error}];
        [[RLMSyncManager sharedManager] _fireError:syncError];
        NSDate *nextFireDate = nil;
        // Certain errors should trigger a retry.
        if (error.domain == NSURLErrorDomain) {
            switch (error.code) {
                case NSURLErrorCannotConnectToHost:
                    // FIXME: 120 seconds is an arbitrarily chosen value, consider rationalizing it.
                    nextFireDate = [NSDate dateWithTimeIntervalSinceNow:120];
                    break;
                case NSURLErrorNotConnectedToInternet:
                case NSURLErrorNetworkConnectionLost:
                case NSURLErrorTimedOut:
                case NSURLErrorDNSLookupFailed:
                case NSURLErrorCannotFindHost:
                    // FIXME: 30 seconds is an arbitrarily chosen value, consider rationalizing it.
                    nextFireDate = [NSDate dateWithTimeIntervalSinceNow:30];
                    break;
                default:
                    break;
            }
            if (nextFireDate) {
                [self scheduleRefreshTimer:nextFireDate];
            } else {
                [user _unregisterRefreshHandleForURLPath:self.pathToRealm];
                [self.timer invalidate];
            }
        }
    };
    [RLMNetworkClient postRequestToEndpoint:RLMServerEndpointAuth
                                     server:user.authenticationServer
                                       JSON:json
                                 completion:handler];
}

@end
