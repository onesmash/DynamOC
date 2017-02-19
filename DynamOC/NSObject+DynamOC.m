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

@implementation NSObject (DynamOC)

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

+ (void)__setLuaLambda:(NSData *)lambda forKey:(NSString *)selector
{
    NSMutableDictionary *lambdas = self.__luaLambdas;
    [lambdas setObject:lambda forKey:selector];
}

@end
