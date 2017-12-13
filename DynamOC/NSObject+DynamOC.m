//
//  NSObject+DynamOC.m
//  DynamOC
//
//  Created by 徐晖 on 2017/1/11.
//  Copyright © 2017年 徐晖. All rights reserved.
//

#import "NSObject+DynamOC.h"
#import <objc/runtime.h>

static char kLuaLambdasKey;
static char KClassMethodDescCacheKey;
static char KInstanceMethodDescCacheKey;

@implementation NSObject (DynamOC)

+ (DynamMethod *)__findDynamMethod:(SEL)sel
{
    DynamMethod *method = [[self __luaLambdas] objectForKey:[NSString stringWithUTF8String:sel_getName(sel)]];
    if(!method) {
        method = [class_getSuperclass(self) __findDynamMethod:sel];
        if(method) {
            [self __setLuaLambda:method forKey:[NSString stringWithUTF8String:sel_getName(sel)]];
        }
    }
    return method;
}

+ (NSMutableDictionary *)__luaLambdas
{
    NSMutableDictionary *lambdas = objc_getAssociatedObject(self, &kLuaLambdasKey);
    if(lambdas) {
        return lambdas;
    }
    lambdas = [NSMutableDictionary dictionary];
    objc_setAssociatedObject(self, &kLuaLambdasKey, lambdas, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return lambdas;
}

+ (void)__setLuaLambda:(DynamMethod *)lambda forKey:(NSString *)selector
{
    NSAssert([NSThread isMainThread], @"Add lua method must in main thread!");
    NSMutableDictionary *lambdas = self.__luaLambdas;
    [lambdas setObject:lambda forKey:selector];
}

+ (NSCache *)__classMethodDescCache
{
    static NSCache *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[NSCache alloc] init];
    });
    return cache;
}

+ (NSCache *)__instanceMethodDescCache
{
    static NSCache *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[NSCache alloc] init];
    });
    return cache;
}

@end
