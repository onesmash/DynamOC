//
//  DynamMethod.m
//  Pods
//
//  Created by Xuhui on 07/03/2017.
//
//

#import "DynamMethod.h"

@interface DynamMethod ()

@end

@implementation DynamMethod

- (instancetype)initWithCode:(NSData *)code upvalues:(NSArray<DynamUpvalue *> *)upvalues
{
    self = [self init];
    if(self) {
        _codeDump = code;
        _upvalueDump = upvalues;
    }
    return self;
}

@end
