//
//  LuaContext+Private.h
//  Pods
//
//  Created by Xuhui on 10/04/2017.
//
//

#import "LuaContext.h"

@interface LuaContext (Private)

+ (NSBundle *)dynamOCBundle;
+ (LuaContext *)currentContext;
+ (LuaContext *)contextForThread:(NSThread *)thread;
+ (void)pushContext:(LuaContext *)context;
+ (void)popContext;

@end

@class DynamBlock;
@class DynamUpvalue;

void forward_invocation(id target, SEL selector, id invocation);
void forward_block_id_invocation(NSInteger blockID, id invocation);
void forward_block_code_invocation(NSData *code, NSArray<DynamUpvalue *> *upvalues, id invocation);
LuaContext *get_luacontext(NSThread *thread);
void push_luacontext(LuaContext *context);
void pop_luacontext();
void free_method(NSInteger methodID);
void free_block(NSInteger blockID);
NSData *dump_block_code(NSInteger blockID);
NSArray<DynamUpvalue *> *dump_block_upvalue(NSInteger blockID);
