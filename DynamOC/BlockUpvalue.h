//
//  BlockUpvalue.h
//  Pods
//
//  Created by Xuhui on 01/03/2017.
//
//

#import <Foundation/Foundation.h>

@interface BlockUpvalue : NSObject

@property (nonatomic, assign) NSInteger index;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) id value;

@end
