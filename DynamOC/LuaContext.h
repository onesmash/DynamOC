//
//  LuaContext.h
//  DynamOC
//
//  Created by 徐晖 on 2017/1/12.
//  Copyright © 2017年 徐晖. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface LuaContext : NSObject

@property (nonatomic, strong) id paramRegister;
@property (nonatomic, strong) id returnValueRegister;

- (BOOL)evaluateScript:(NSString *)script;

@end

void forward_invocation(id target, SEL selector, id invocation);
id get_luacontext();

