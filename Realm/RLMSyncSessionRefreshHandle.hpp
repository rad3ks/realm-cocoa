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

#import "RLMSyncSessionRefreshHandle.h"

#import "RLMSyncUtil_Private.h"

#import <memory>

namespace realm {
class SyncSession;
}

@class RLMSyncUser;

/// An object that handles refreshing a session's auth token periodically, as long as that session remains viable.
/// Intended for easy removal once the new auth system is in place.
@interface RLMSyncSessionRefreshHandle ()

NS_ASSUME_NONNULL_BEGIN

- (instancetype)initWithRealmURL:(NSURL *)realmURL
                            user:(RLMSyncUser *)user
                         session:(std::shared_ptr<realm::SyncSession>)session
                 completionBlock:(nullable RLMSyncBasicErrorReportingBlock)completionBlock;

NS_ASSUME_NONNULL_END

@end
