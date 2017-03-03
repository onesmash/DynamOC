//
//  WeakObject.h
//  Pods
//
//  Created by Xuhui on 01/03/2017.
//
//

#import <Foundation/Foundation.h>

@interface WeakObject : NSProxy

@property (nonatomic, weak) id object;

@end
