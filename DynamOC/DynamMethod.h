//
//  DynamMethod.h
//  Pods
//
//  Created by Xuhui on 07/03/2017.
//
//

#import <Foundation/Foundation.h>

@class DynamUpvalue;

@interface DynamMethod : NSObject

@property (nonatomic, strong) NSData *codeDump;
@property (nonatomic, strong) NSArray<DynamUpvalue *> *upvalueDump;

- (instancetype)initWithCode:(NSData *)code upvalues:(NSArray<DynamUpvalue *> *)upvalues;

@end
