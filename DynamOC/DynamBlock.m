//
//  DynamBlock.m
//  Pods
//
//  Created by Xuhui on 23/02/2017.
//
//

#import "DynamBlock.h"

enum {
    BLOCK_DEALLOCATING =      (0x0001),  // runtime
    BLOCK_REFCOUNT_MASK =     (0xfffe),  // runtime
    BLOCK_NEEDS_FREE =        (1 << 24), // runtime
    BLOCK_HAS_COPY_DISPOSE =  (1 << 25), // compiler
    BLOCK_HAS_CTOR =          (1 << 26), // compiler: helpers have C++ code
    BLOCK_IS_GC =             (1 << 27), // runtime
    BLOCK_IS_GLOBAL =         (1 << 28), // compiler
    BLOCK_USE_STRET =         (1 << 29), // compiler: undefined if !BLOCK_HAS_SIGNATURE
    BLOCK_HAS_SIGNATURE  =    (1 << 30), // compiler
    BLOCK_HAS_EXTENDED_LAYOUT=(1 << 31)  // compiler
};

struct Block {
    void *isa;
    int flags;
    int reserved;
    void (*invoke)(void *, ...);
    struct BlockDescriptor *descriptor;
};



@interface DynamBlock () {
    id block_;
}

@end

@implementation DynamBlock

- (instancetype)initWithBlock:(id)block
{
    self = [self init];
    if(self) {
        block_ = [block copy];
    }
    return self;
}

- (NSString *)signature
{
    struct Block *block = (__bridge struct Block *)block_;
    if(block->flags & BLOCK_HAS_SIGNATURE) {
        void *signatureLocation = block->descriptor;
        signatureLocation += sizeof(block->descriptor->reserved);
        signatureLocation += sizeof(block->descriptor->size);
        
        if(block->flags & BLOCK_HAS_COPY_DISPOSE) {
            signatureLocation = block->descriptor->signature;
        }
        const char *sig = (*(const char **)signatureLocation);
        return [NSString stringWithUTF8String:sig];
    }
    
    return @"";
}

@end
