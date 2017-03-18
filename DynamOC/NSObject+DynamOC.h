//
//  NSObject+DynamOC.h
//  DynamOC
//
//  Created by 徐晖 on 2017/1/11.
//  Copyright © 2017年 徐晖. All rights reserved.
//

#import <Foundation/Foundation.h>

@class DynamMethod;

@interface NSObject (DynamOC)

+ (NSMutableDictionary *)__luaLambdas;
+ (void)__setLuaLambda:(DynamMethod *)lambda forKey:(NSString *)selector;
+ (NSCache *)__classMethodDescCache;
+ (NSCache *)__instanceMethodDescCache;

@end
