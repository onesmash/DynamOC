//
//  WeakObject.m
//  Pods
//
//  Created by Xuhui on 01/03/2017.
//
//

#import "WeakObject.h"

@interface WeakObject ()

@end

@implementation WeakObject

- (instancetype)initWithObject:(id)object
{
    if(self) {
        self = [self init];
        self.object = object;
    }
    return self;
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector
{
    return [self.object methodSignatureForSelector:aSelector];
}

- (void)forwardInvocation:(NSInvocation *)anInvocation
{
    [anInvocation invokeWithTarget:self.object];
}

@end
