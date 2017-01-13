//
//  LuaContext.m
//  DynamOC
//
//  Created by 徐晖 on 2017/1/12.
//  Copyright © 2017年 徐晖. All rights reserved.
//

#import "LuaContext.h"
#import <lua.h>

#define kThreadLocalLuaContextKey @"kThreadLocalLuaContextKey"

@interface LuaContext ()

//@property (nonatomic, assign)

@end

@implementation LuaContext

- (BOOL)evaluateScript:(NSString *)script
{
    return YES;
}

@end

void forward_invocation(id target, SEL selector, id invocation)
{
    
}

id get_luacontext()
{
    @autoreleasepool {
        LuaContext *context = [[NSThread currentThread].threadDictionary objectForKey:kThreadLocalLuaContextKey];
        if(!context) {
            context = [[LuaContext alloc] init];
            [[NSThread currentThread].threadDictionary setObject:context forKey:kThreadLocalLuaContextKey];
        }
        return context;
    }
}
