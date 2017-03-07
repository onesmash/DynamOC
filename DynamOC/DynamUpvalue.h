//
//  DynamUpvalue.h
//  Pods
//
//  Created by Xuhui on 07/03/2017.
//
//

#import <Foundation/Foundation.h>

typedef enum {
    kDynamUpvalueTypeDouble,
    kDynamUpvalueTypeInteger,
    kDynamUpvalueTypeUInteger,
    kDynamUpvalueTypeBoolean,
    kDynamUpvalueTypeString,
    kDynamUpvalueTypeBytes,
    kDynamUpvalueTypeObject,
} DynamUpvalueType;

@interface DynamUpvalue : NSObject

@property (nonatomic, assign) NSInteger index;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) id value;
@property (nonatomic, copy) NSString *cType;
@property (nonatomic, assign) DynamUpvalueType type;

@end
