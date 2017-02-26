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

+ (NSBundle *)dynamOCBundle;
+ (LuaContext *)currentContext;

- (BOOL)evaluateScript:(NSString *)code;

@end

@class DynamBlock;

void forward_invocation(id target, SEL selector, id invocation);
void forward_block_invocation(NSInteger blockID, id invocation);
id get_luacontext();
DynamBlock *create_block(NSInteger blockID, const char* signature);
void free_block(NSInteger blockID);

