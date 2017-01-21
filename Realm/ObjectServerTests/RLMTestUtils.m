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

#import <Foundation/Foundation.h>

#import "RLMTestUtils.h"

#import <objc/runtime.h>

void rlmTestUtils_swapOutMethod(id classObject, SEL original, SEL swizzled, BOOL isClass);

void rlmTestUtils_swapOutMethod(id classObject, SEL original, SEL swizzled, BOOL isClass) {
    Class class = isClass ? object_getClass((id)classObject) : [classObject class];
    Method originalMethod = (isClass
                             ? class_getClassMethod(class, original)
                             : class_getInstanceMethod(class, original));
    Method swizzledMethod = (isClass
                             ? class_getClassMethod(class, swizzled)
                             : class_getInstanceMethod(class, swizzled));

    if (class_addMethod(class,
                        original,
                        method_getImplementation(swizzledMethod),
                        method_getTypeEncoding(swizzledMethod))) {
        class_replaceMethod(class,
                            swizzled,
                            method_getImplementation(originalMethod),
                            method_getTypeEncoding(originalMethod));
    } else {
        method_exchangeImplementations(originalMethod, swizzledMethod);
    }
}

void rlmTestUtils_swapOutClassMethod(id classObject, SEL original, SEL swizzled) {
    rlmTestUtils_swapOutMethod(classObject, original, swizzled, YES);
}

void rlmTestUtils_swapOutInstanceMethod(id classObject, SEL original, SEL swizzled) {
    rlmTestUtils_swapOutMethod(classObject, original, swizzled, NO);
}
