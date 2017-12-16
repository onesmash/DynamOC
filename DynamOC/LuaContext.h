//
//  LuaContext.h
//  DynamOC
//
//  Created by 徐晖 on 2017/1/12.
//  Copyright © 2017年 徐晖. All rights reserved.
//

#import <Foundation/Foundation.h>

#define kDynamOCErrorDomain @"me.onesmash.dynamoc"

typedef enum : NSUInteger {
    DynamOCErrorCodeLuaCompileError = 1,
    DynamOCErrorCodeLuaRunError,
} DynamOCErrorCode;

@interface LuaContext : NSObject

+ (LuaContext *)currentContext;
- (BOOL)evaluateScript:(NSString *)code error:(NSError **)error;

@end

