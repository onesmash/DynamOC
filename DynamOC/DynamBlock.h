//
//  DynamBlock.h
//  Pods
//
//  Created by Xuhui on 23/02/2017.
//
//

#import <Foundation/Foundation.h>

struct BlockDescriptor {
    uintptr_t reserved;         // NULL
    uintptr_t size;         // sizeof(struct Block_literal_1)
};

@interface DynamBlock : NSObject <NSCopying> {
    int flags;
    int reserved;
    void (*invoke)(void *, ...);
    struct BlockDescriptor *descriptor;
}

@property (nonatomic, assign) NSInteger blockID;
@property (nonatomic, copy) NSString *signature;
@property (nonatomic, assign) BOOL syncDispatch;

- (instancetype)initWithBlockID:(NSInteger)callId signature:(NSString *)sig;
@end
