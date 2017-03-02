//
//  BlockUpvalue.h
//  Pods
//
//  Created by Xuhui on 01/03/2017.
//
//

#import <Foundation/Foundation.h>

typedef enum {
    kBlockUpvalueTypeDouble,
    kBlockUpvalueTypeInteger,
    kBlockUpvalueTypeUInteger,
    kBlockUpvalueTypeBoolean,
    kBlockUpvalueTypeString,
    kBlockUpvalueTypeBytes,
    kBlockUpvalueTypeObject,
} BlockUpvalueType;

@interface BlockUpvalue : NSObject
@property (nonatomic, assign) NSInteger index;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) id value;
@property (nonatomic, copy) NSString *cType;
@property (nonatomic, assign) BlockUpvalueType type;

@end
