//
//  LuaContext.h
//  DynamOC
//
//  Created by 徐晖 on 2017/1/12.
//  Copyright © 2017年 徐晖. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface LuaContext : NSObject

- (BOOL)evaluateScript:(NSString *)code;

@end

LuaContext *get_current_luacontext();

