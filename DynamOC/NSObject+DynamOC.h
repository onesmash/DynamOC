//
//  NSObject+DynamOC.h
//  DynamOC
//
//  Created by 徐晖 on 2017/1/11.
//  Copyright © 2017年 徐晖. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSObject (DynamOC)

+ (NSMutableDictionary *)__luaLambdas;
+ (void)__setLuaLambda:(NSString *)lambda forKey:(NSString *)selector;

@end
