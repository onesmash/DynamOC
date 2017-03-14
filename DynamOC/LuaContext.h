//
//  LuaContext.h
//  DynamOC
//
//  Created by 徐晖 on 2017/1/12.
//  Copyright © 2017年 徐晖. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface LuaContext : NSObject

@property (nonatomic, strong) id argumentRegister;
@property (nonatomic, strong) id returnRegister;

+ (NSBundle *)dynamOCBundle;
+ (LuaContext *)currentContext;
+ (LuaContext *)contextForThread:(NSThread *)thread;
+ (void)pushContext:(LuaContext *)context;
+ (void)popContext;


- (BOOL)evaluateScript:(NSString *)code;

@end

@class DynamBlock;
@class DynamUpvalue;

void forward_invocation(id target, SEL selector, id invocation);
void forward_block_id_invocation(NSInteger blockID, id invocation);
void forward_block_code_invocation(NSData *code, NSArray<DynamUpvalue *> *upvalues, id invocation);
LuaContext *get_luacontext(NSThread *thread);
LuaContext *get_current_luacontext();
void push_luacontext(LuaContext *context);
void pop_luacontext();
void free_method(NSInteger methodID);
void free_block(NSInteger blockID);
NSData *dump_block_code(NSInteger blockID);
NSArray<DynamUpvalue *> *dump_block_upvalue(NSInteger blockID);

