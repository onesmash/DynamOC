//
//  LuaContext.m
//  DynamOC
//
//  Created by 徐晖 on 2017/1/12.
//  Copyright © 2017年 徐晖. All rights reserved.
//

#import "LuaContext.h"
#import "NSObject+DynamOC.h"
#import <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#define kThreadLocalLuaContextKey @"kThreadLocalLuaContextKey"

@interface LuaContext () {
    lua_State *_L;
}

@end

@implementation LuaContext

- (instancetype)init
{
    self = [super init];
    if(self) {
        _L = luaL_newstate();
        if(_L) {
            luaL_openlibs(_L );
        }
    }
    return self;
}

- (BOOL)evaluateScript:(NSString *)script
{
    lua_getglobal(_L, "debug");
    lua_getfield(_L, -1, "traceback");
    lua_getglobal(_L, "objc");
    lua_getfield(_L, -1, "evaluate");
    lua_pushstring(_L, script.UTF8String);
    BOOL ret = YES;
    if(lua_pcall(_L, 1, 0, -3)) {
        NSLog(@"Uncaught Error:  %@", [NSString stringWithUTF8String:lua_tostring(_L, -1)]);
        ret = NO;
    }
    lua_pop(_L, 4);
    return YES;
}

@end

void forward_invocation(NSObject *target, SEL selector, id invocation)
{
    LuaContext *context = get_luacontext();
    context.argumentRegister = invocation;
    NSString *luaCode = [[target.class __luaLambdas] objectForKey:[NSString stringWithUTF8String:sel_getName(selector)]];
    SEL sel = NSSelectorFromString(@"__forwardInvocation:");
    if(luaCode) {
        [context evaluateScript:luaCode];
    } else if([target respondsToSelector:sel]) {
        [target performSelector:sel withObject:invocation];
    }
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
