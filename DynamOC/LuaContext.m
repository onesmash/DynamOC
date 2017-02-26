//
//  LuaContext.m
//  DynamOC
//
//  Created by 徐晖 on 2017/1/12.
//  Copyright © 2017年 徐晖. All rights reserved.
//

#import "LuaContext.h"
#import "NSObject+DynamOC.h"
#import "DynamBlock.h"
#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#define kThreadLocalLuaContextKey @"kThreadLocalLuaContextKey"

static int register_lambda(lua_State *L)
{
    lua_pushvalue(L, -1);
    int closureId = luaL_ref(L, LUA_REGISTRYINDEX);
    lua_pushinteger(L, closureId);
    return 1;
}

@interface LuaContext () {
    lua_State *_L;
}

@property (nonatomic, weak) NSThread *thread;

@end

@implementation LuaContext

+ (NSBundle *)dynamOCBundle
{
    NSBundle *superBundle = [NSBundle bundleForClass:[LuaContext class]];
    NSURL *bundleURL = [superBundle URLForResource:@"DynamOC" withExtension:@"bundle"];
    return [NSBundle bundleWithURL:bundleURL];
}

+ (LuaContext *)currentContext
{
    LuaContext *context = [[NSThread currentThread].threadDictionary objectForKey:kThreadLocalLuaContextKey];
    if(!context) {
        context = [[LuaContext alloc] init];
        [[NSThread currentThread].threadDictionary setObject:context forKey:kThreadLocalLuaContextKey];
    }
    return context;
}

- (instancetype)init
{
    self = [super init];
    if(self) {
        self.thread = [NSThread currentThread];
        _L = luaL_newstate();
        if(_L) {
            luaL_openlibs(_L );
            NSString *scriptDirectory = [[LuaContext dynamOCBundle] resourcePath];
            lua_pushstring(_L, scriptDirectory.UTF8String);
            lua_setglobal(_L, "__scriptDirectory");
            NSString *bootFilePath = [[LuaContext dynamOCBundle] pathForResource:@"boot" ofType:@"lua"];
            lua_getglobal(_L, "debug");
            lua_getfield(_L, -1, "traceback");
            lua_replace(_L, -2);
            do {
                if (luaL_loadfile(_L,  bootFilePath.UTF8String) == 0) {
                    if(lua_pcall(_L, 0, 0, -2)) {
                        NSLog(@"Uncaught Error:  %@", [NSString stringWithUTF8String:lua_tostring(_L, -1)]);
                        lua_pop(_L, 2);
                        break;
                    }
                    lua_pop(_L, 1);
                    lua_getglobal(_L, "runtime");
                    lua_pushcfunction(_L, register_lambda);
                    lua_setfield(_L, -2, "registerLambda");
                    lua_pop(_L, 1);
                    break;
                }
                lua_pop(_L, 2);
            } while (false);
        }
    }
    return self;
}

- (BOOL)evaluateScript:(NSString *)code
{
    BOOL ret = YES;
    lua_getglobal(_L, "debug");
    lua_getfield(_L, -1, "traceback");
    lua_replace(_L, -2);
    if(luaL_loadstring(_L, code.UTF8String) == 0) {
        if(lua_pcall(_L, 0, 0, -2)) {
            NSLog(@"Uncaught Error:  %@", [NSString stringWithUTF8String:lua_tostring(_L, -1)]);
            lua_pop(_L, 2);
            return NO;
        }
        lua_pop(_L, 1);
        return YES;
    }
    lua_pop(_L, 2);
    return NO;
}

- (BOOL)forwardMethodInvocation:(NSData *)script
{
    lua_getglobal(_L, "debug");
    lua_getfield(_L, -1, "traceback");
    lua_replace(_L, -2);
    lua_getglobal(_L, "runtime");
    lua_getfield(_L, -1, "evaluateMethod");
    lua_replace(_L, -2);
    lua_pushlightuserdata(_L, script.bytes);
    lua_pushnumber(_L, script.length);
    if(lua_pcall(_L, 2, 0, -4)) {
        NSLog(@"Uncaught Error:  %@", [NSString stringWithUTF8String:lua_tostring(_L, -1)]);
        lua_pop(_L, 2);
        return NO;
    }
    lua_pop(_L, 1);
    return YES;
}

- (BOOL)forwardBlockInvocation:(NSInteger)callId
{
    lua_getglobal(_L, "debug");
    lua_getfield(_L, -1, "traceback");
    lua_replace(_L, -2);
    lua_getglobal(_L, "runtime");
    lua_getfield(_L, -1, "evaluateBlock");
    lua_replace(_L, -2);
    lua_rawgeti(_L, LUA_REGISTRYINDEX, callId);
    if(lua_pcall(_L, 1, 0, -3)) {
        NSLog(@"Uncaught Error:  %@", [NSString stringWithUTF8String:lua_tostring(_L, -1)]);
        lua_pop(_L, 2);
        return NO;
    }
    lua_pop(_L, 1);
    return YES;
}

- (void)freeLuaBlock:(NSInteger)blockID
{
    lua_unref(_L, blockID);
}

@end

void forward_invocation(NSObject *target, SEL selector, NSInvocation *invocation)
{
    LuaContext *context = get_luacontext();
    context.argumentRegister = invocation;
    NSData *luaCodeData = [[target.class __luaLambdas] objectForKey:[NSString stringWithUTF8String:sel_getName(invocation.selector)]];
    SEL sel = NSSelectorFromString(@"__forwardInvocation:");
    if(luaCodeData) {
        [context forwardMethodInvocation:luaCodeData];
    } else if([target respondsToSelector:sel]) {
        [target performSelector:sel withObject:invocation];
    }
}

void forward_block_invocation(NSInteger callId, id invocation)
{
    LuaContext *context = get_luacontext();
    context.argumentRegister = invocation;
    [context forwardBlockInvocation:callId];
}

id get_luacontext()
{
    @autoreleasepool {
        return [LuaContext currentContext];
    }
}

DynamBlock *create_block(NSInteger blockID, const char* signature)
{
    @autoreleasepool {
        DynamBlock *block = [[DynamBlock alloc] initWithBlockID:blockID signature:[NSString stringWithUTF8String:signature]];
        return block;
    }
}

void free_block(NSInteger blockID)
{
    @autoreleasepool {
        LuaContext *context = get_luacontext();
        [context freeLuaBlock:blockID];
    }
}
