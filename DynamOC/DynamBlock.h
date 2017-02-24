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
    // optional helper functions
    void (*copy_helper)(void *dst, void *src);     // IFF (1<<25)
    void (*dispose_helper)(void *src);             // IFF (1<<25)
    // required ABI.2010.3.16
    const char *signature;                         // IFF (1<<30)
};

@interface DynamBlock : NSObject {
    int flags;
    int reserved;
    void (*invoke)(void *, ...);
    struct BlockDescriptor *descriptor;
}

- (instancetype)initWithBlock:(id)block;

- (NSString *)signature;

@end
