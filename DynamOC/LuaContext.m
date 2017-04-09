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
#import "DynamMethod.h"
#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
#import <objc/runtime.h>

#define kThreadLocalLuaContextKey @"kThreadLocalLuaContextKey"

NSInteger kInvalidMethodID = -1;

static int buf_writer( lua_State *L, const void* b, size_t n, void *B ) {
    luaL_addlstring((luaL_Buffer *)B, (const char *)b, n);
    return 0;
}

static int register_lambda(lua_State *L)
{
    lua_pushvalue(L, -1);
    int closureId = luaL_ref(L, LUA_REGISTRYINDEX);
    lua_pushinteger(L, closureId);
    return 1;
}

@interface DynamMethodDesc : NSObject

@property (nonatomic, copy) NSString *methodTypeEncoding;
@property (nonatomic, assign) SEL sel;
@property (nonatomic, assign) BOOL isSpecialStructReturn;

@end

@implementation DynamMethodDesc
@end

@interface DynamMethodCache : NSObject {
}

@property (nonatomic, weak) NSThread *thread;
@property (nonatomic, assign) NSInteger methodID;

@end

@implementation DynamMethodCache

- (void)dealloc
{
    [self performSelector:@selector(cleanup) onThread:self.thread withObject:nil waitUntilDone:YES];
}

- (void)cleanup
{
    free_method(_methodID);
}

@end

@interface LuaContext () {
    lua_State *_L;
}

@property (nonatomic, weak) NSThread *thread;
@property (nonatomic, strong) NSCache *methodCache;

@end

@implementation LuaContext

+ (NSBundle *)dynamOCBundle
{
    NSBundle *superBundle = [NSBundle bundleForClass:[LuaContext class]];
    NSURL *bundleURL = [superBundle URLForResource:@"DynamOC" withExtension:@"bundle"];
    return [NSBundle bundleWithURL:bundleURL];
}

+ (NSLock *)contextLock
{
    static NSLock *lock;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        lock = [[NSLock alloc] init];
    });
    return lock;
}

+ (LuaContext *)currentContext
{
    return [self contextForThread:[NSThread currentThread]];
}

+ (LuaContext *)contextForThread:(NSThread *)thread
{
    [self contextLock].lock;
    NSMutableArray<LuaContext *> *contexts = [thread.threadDictionary objectForKey:kThreadLocalLuaContextKey];
    if(!contexts || contexts.count <= 0) {
        contexts = [NSMutableArray array];
        LuaContext *context = [[LuaContext alloc] init];
        [contexts addObject:context];
        [thread.threadDictionary setObject:contexts forKey:kThreadLocalLuaContextKey];
    }
    LuaContext *context = contexts.lastObject;
    [self contextLock].unlock;
    return context;
}

+ (void)pushContext:(LuaContext *)context
{
    [self contextLock].lock;
    NSMutableArray<LuaContext *> *contexts = [[NSThread currentThread].threadDictionary objectForKey:kThreadLocalLuaContextKey];
    if(!contexts) {
        contexts = [NSMutableArray array];
        [[NSThread currentThread].threadDictionary setObject:contexts forKey:kThreadLocalLuaContextKey];
    }
    [contexts addObject:context];
    [self contextLock].unlock;
}

+ (void)popContext
{
    [self contextLock].lock;
    NSMutableArray<LuaContext *> *contexts = [[NSThread currentThread].threadDictionary objectForKey:kThreadLocalLuaContextKey];
    [contexts removeLastObject];
    [self contextLock].unlock;
}

- (instancetype)init
{
    self = [super init];
    if(self) {
        self.thread = [NSThread currentThread];
        _methodCache = [[NSCache alloc] init];
        _L = luaL_newstate();
        if(_L) {
            luaL_openlibs(_L );
            NSString *scriptDirectory = [[LuaContext dynamOCBundle] resourcePath];
            lua_pushstring(_L, scriptDirectory.UTF8String);
            lua_setglobal(_L, "__scriptDirectory");
            NSString *bootFilePath = [[LuaContext dynamOCBundle] pathForResource:@"boot" ofType:@"luac"];
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
    lua_pop(_L, 1);
    return NO;
}

- (BOOL)forwardMethodCodeInvocation:(DynamMethod *)method
{
    lua_getglobal(_L, "debug");
    lua_getfield(_L, -1, "traceback");
    lua_replace(_L, -2);
    lua_getglobal(_L, "runtime");
    lua_getfield(_L, -1, "evaluateMethodCode");
    lua_replace(_L, -2);
    lua_pushlightuserdata(_L, (void *)method.codeDump.bytes);
    lua_pushnumber(_L, method.codeDump.length);
    if(lua_pcall(_L, 2, 1, -4)) {
        NSLog(@"Uncaught Error:  %@", [NSString stringWithUTF8String:lua_tostring(_L, -1)]);
        lua_pop(_L, 2);
        return NO;
    }
    NSInteger methodID = lua_tointeger(_L, -1);
    lua_pop(_L, 2);
    if(methodID != kInvalidMethodID) {
        DynamMethodCache *methodCache = [[DynamMethodCache alloc] init];
        methodCache.methodID = methodID;
        methodCache.thread = [NSThread currentThread];
        [self.methodCache setObject:methodCache forKey:method];
    }
    return YES;
}

- (BOOL)forwardMethodIDInvocation:(NSInteger)methodID
{
    lua_getglobal(_L, "debug");
    lua_getfield(_L, -1, "traceback");
    lua_replace(_L, -2);
    lua_getglobal(_L, "runtime");
    lua_getfield(_L, -1, "evaluateMethod");
    lua_replace(_L, -2);
    lua_rawgeti(_L, LUA_REGISTRYINDEX, methodID);
    if(lua_pcall(_L, 1, 0, -3)) {
        NSLog(@"Uncaught Error:  %@", [NSString stringWithUTF8String:lua_tostring(_L, -1)]);
        lua_pop(_L, 2);
        return NO;
    }
    lua_pop(_L, 1);
    return YES;
}

- (BOOL)forwardBlockIDInvocation:(NSInteger)blockID
{
    lua_getglobal(_L, "debug");
    lua_getfield(_L, -1, "traceback");
    lua_replace(_L, -2);
    lua_getglobal(_L, "runtime");
    lua_getfield(_L, -1, "evaluateBlock");
    lua_replace(_L, -2);
    lua_rawgeti(_L, LUA_REGISTRYINDEX, blockID);
    if(lua_pcall(_L, 1, 0, -3)) {
        NSLog(@"Uncaught Error:  %@", [NSString stringWithUTF8String:lua_tostring(_L, -1)]);
        lua_pop(_L, 2);
        return NO;
    }
    lua_pop(_L, 1);
    return YES;
}

- (BOOL)forwardBlockCodeInvocation:(NSData *)code
{
    lua_getglobal(_L, "debug");
    lua_getfield(_L, -1, "traceback");
    lua_replace(_L, -2);
    lua_getglobal(_L, "runtime");
    lua_getfield(_L, -1, "evaluateBlockCode");
    lua_replace(_L, -2);
    lua_pushlightuserdata(_L, code.bytes);
    lua_pushnumber(_L, code.length);
    if(lua_pcall(_L, 2, 0, -4)) {
        NSLog(@"Uncaught Error:  %@", [NSString stringWithUTF8String:lua_tostring(_L, -1)]);
        lua_pop(_L, 2);
        return NO;
    }
    lua_pop(_L, 1);
    return YES;
}

- (void)freeLuaMethod:(NSInteger)methodID
{
    lua_unref(_L, methodID);
}

- (void)freeLuaBlock:(NSInteger)blockID
{
    lua_unref(_L, blockID);
}

- (NSData *)dumpLuaBlockCode:(NSInteger)blockID
{
    lua_rawgeti(_L, LUA_REGISTRYINDEX, blockID);
    luaL_Buffer b;
    luaL_buffinit(_L, &b);
    lua_dump(_L, buf_writer, &b);
    luaL_pushresult(&b);
    size_t size;
    const char *code = lua_tolstring(_L, -1, &size);
    NSData *data = [NSData dataWithBytes:code length:size];
    lua_pop(_L, 2);
    return data;
}

- (NSArray *)dumpLuaBlockUpvalue:(NSInteger)blockID
{
    lua_getglobal(_L, "debug");
    lua_getfield(_L, -1, "traceback");
    lua_replace(_L, -2);
    lua_getglobal(_L, "runtime");
    lua_getfield(_L, -1, "dumpBlockUpvalues");
    lua_replace(_L, -2);
    lua_rawgeti(_L, LUA_REGISTRYINDEX, blockID);
    if(lua_pcall(_L, 1, 0, -3)) {
        NSLog(@"Uncaught Error:  %@", [NSString stringWithUTF8String:lua_tostring(_L, -1)]);
        lua_pop(_L, 2);
        return nil;
    }
    lua_pop(_L, 1);
    return self.returnRegister;
}

@end

void forward_invocation(NSObject *target, SEL selector, NSInvocation *invocation)
{
    @autoreleasepool {
        DynamMethod *method = [[target.class __luaLambdas] objectForKey:[NSString stringWithUTF8String:sel_getName(invocation.selector)]];
        SEL sel = NSSelectorFromString(@"__forwardInvocation:");
        if(method) {
            LuaContext *context = get_current_luacontext();
            DynamMethodCache *methodCache = [context.methodCache objectForKey:method];
            if(methodCache) {
                context.argumentRegister = @[invocation];
                [context forwardMethodIDInvocation:methodCache.methodID];
            } else {
                context.argumentRegister = @[method.upvalueDump, invocation];
                [context forwardMethodCodeInvocation:method];
            }
        } else if([target respondsToSelector:sel]) {
            [target performSelector:sel withObject:invocation];
        }
    }
}

void forward_block_id_invocation(NSInteger callId, id invocation)
{
    @autoreleasepool {
        LuaContext *context = get_current_luacontext();
        context.argumentRegister = invocation;
        [context forwardBlockIDInvocation:callId];
    }
}

void forward_block_code_invocation(NSData *code, NSArray<DynamUpvalue *> *upvalues, id invocation)
{
    @autoreleasepool {
        LuaContext *context = get_current_luacontext();
        context.argumentRegister = @[upvalues, invocation];
        [context forwardBlockCodeInvocation:code];
    }
}

LuaContext *get_luacontext(NSThread *thread)
{
    @autoreleasepool {
        return [LuaContext contextForThread:thread];
    }
}

LuaContext *get_current_luacontext()
{
    @autoreleasepool {
        return [LuaContext contextForThread:[NSThread currentThread]];
    }
}

void push_luacontext(LuaContext *context)
{
    @autoreleasepool {
        [LuaContext pushContext:context];
    }
}

void pop_luacontext()
{
    @autoreleasepool {
        [LuaContext popContext];
    }
}

DynamBlock *create_block(NSInteger blockID, const char* signature)
{
    @autoreleasepool {
        DynamBlock *block = [[DynamBlock alloc] initWithBlockID:blockID signature:[NSString stringWithUTF8String:signature]];
        return block;
    }
}

void free_method(NSInteger methodID)
{
    @autoreleasepool {
        LuaContext *context = get_current_luacontext();
        [context freeLuaMethod:methodID];
    }
}

void free_block(NSInteger blockID)
{
    @autoreleasepool {
        LuaContext *context = get_current_luacontext();
        [context freeLuaBlock:blockID];
    }
}

NSData *dump_block_code(NSInteger blockID)
{
    @autoreleasepool {
        LuaContext *context = get_current_luacontext();
        return [context dumpLuaBlockCode:blockID];
    }
}

NSArray<DynamUpvalue *> *dump_block_upvalue(NSInteger blockID)
{
    @autoreleasepool {
        LuaContext *context = get_current_luacontext();
        context.returnRegister = [NSMutableArray array];
        return [context dumpLuaBlockUpvalue:blockID];
    }
}

NSString *selectorStringFromMethodNameWithUnderscores(const char *name)
{
    @autoreleasepool {
        NSInteger len = strlen(name);
        char selName[len + 1];
        selName[len] = '\0';
        NSInteger colonIndex = len;
        for (NSInteger i = len - 1; i >= 0 ; i--) {
            char c = name[i];
            selName[i] = c;
            if(c == '_') {
                colonIndex = i;
                continue;
            }
            if(colonIndex < len) {
                selName[colonIndex] = ':';
            }
        }
        return [NSString stringWithUTF8String:selName];
    }
}

DynamMethodDesc *dynamMethodDescFromMethodNameWithUnderscores(id object, const char *name, BOOL isClass)
{
    @autoreleasepool {
        NSCache *cache = isClass ? [object __classMethodDescCache] : [[object class] __instanceMethodDescCache];
        NSString *key = [NSString stringWithUTF8String:name];
        DynamMethodDesc *desc = [cache objectForKey:key];
        if(!desc) {
            NSString *selStr = selectorStringFromMethodNameWithUnderscores(name);
            SEL sel = NSSelectorFromString(selStr);
            NSMethodSignature *sig = [object methodSignatureForSelector:sel];
            NSMutableString *typeEncoding = [NSMutableString string];
            [typeEncoding appendString:[NSString stringWithUTF8String:sig.methodReturnType]];
            for (NSInteger i = 0; i < sig.numberOfArguments; i++) {
                [typeEncoding appendString:[NSString stringWithUTF8String:[sig getArgumentTypeAtIndex:i]]];
            }
            BOOL isSpecialStructReturn = NO;
#if !defined(__arm64__)
            if ([typeEncoding hasPrefix:@"{"]) {
                //In some cases that returns struct, we should use the '_stret' API:
                //http://sealiesoftware.com/blog/archive/2008/10/30/objc_explain_objc_msgSend_stret.html
                //NSMethodSignature knows the detail but has no API to return, we can only get the info from debugDescription.
                if ([sig.debugDescription rangeOfString:@"is special struct return? YES"].location != NSNotFound) {
                    isSpecialStructReturn = YES;
                }
            }
#endif
            desc = [[DynamMethodDesc alloc] init];
            desc.methodTypeEncoding = typeEncoding;
            desc.isSpecialStructReturn = isSpecialStructReturn;
            desc.sel = sel;
            [cache setObject:desc forKey:key];
        }
        return desc;
    }
}

const char* methodTypeFromDynamMethodDesc(DynamMethodDesc *desc)
{
    @autoreleasepool {
        return desc.methodTypeEncoding.UTF8String;
    }
}

BOOL isSpecialStructReturnFromDynamMethodDesc(DynamMethodDesc *desc)
{
    @autoreleasepool {
        return desc.isSpecialStructReturn;
    }
}

SEL selFromDynamMethodDesc(DynamMethodDesc *desc)
{
    @autoreleasepool {
        return desc.sel;
    }
}
