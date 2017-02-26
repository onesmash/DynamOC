//
//  DynamBlock.m
//  Pods
//
//  Created by Xuhui on 23/02/2017.
//
//

#import "DynamBlock.h"
#import "LuaContext.h"
#import <objc/message.h>

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

static const char *get_block_signature(id b)
{
    struct Block *block = (__bridge struct Block *)b;
    if(block->flags & BLOCK_HAS_SIGNATURE) {
        void *signatureLocation = block->descriptor;
        signatureLocation += sizeof(block->descriptor->reserved);
        signatureLocation += sizeof(block->descriptor->size);
        
        if(block->flags & BLOCK_HAS_COPY_DISPOSE) {
            signatureLocation = block->descriptor->signature;
        }
        const char *sig = (*(const char **)signatureLocation);
        return sig;
    }
}

@interface DynamBlock () {
    id block_;
}

@property (nonatomic, weak) NSThread *thread;
@property (nonatomic, assign) BOOL copyed;

@end

@implementation DynamBlock

- (instancetype)initWithBlockID:(NSInteger)blockID signature:(NSString *)sig
{
    self = [self init];
    if(self) {
        self.copyed = NO;
        self.blockID = blockID;
        self.signature = sig;
        flags = BLOCK_HAS_SIGNATURE;
        IMP msgForwardIMP = _objc_msgForward;
#if !defined(__arm64__)
        if([sig hasPrefix:@"{"]) {
            NSMethodSignature *methodSignature = [NSMethodSignature signatureWithObjCTypes:sig.UTF8String];
            if ([methodSignature.debugDescription rangeOfString:@"is special struct return? YES"].location != NSNotFound) {
                msgForwardIMP = (IMP)_objc_msgForward_stret;
                flags &= BLOCK_USE_STRET;
            }
        }
#endif
        invoke = msgForwardIMP;
        descriptor = malloc(sizeof(struct BlockDescriptor));
        descriptor->size = class_getInstanceSize([self class]);
        descriptor->signature = self.signature.UTF8String;
    }
    return self;
}

- (instancetype)initWithBlock:(id)block
{
    self = [self init];
    if(self) {
        block_ = [block copy];
        
        // The bottom 16 bits represent the block's retain count
        struct Block *block = (__bridge struct Block *)block_;
        flags = block->flags & ~0xFFFF;
        descriptor = malloc(sizeof(struct BlockDescriptor));
        descriptor->size = class_getInstanceSize([self class]);
        if(flags & BLOCK_HAS_SIGNATURE) {
            void *signatureLocation = block->descriptor;
            signatureLocation += sizeof(block->descriptor->reserved);
            signatureLocation += sizeof(block->descriptor->size);
            
            if(block->flags & BLOCK_HAS_COPY_DISPOSE) {
                signatureLocation = block->descriptor->signature;
            }
            signatureLocation = get_block_signature(block_);
        }
        
        invoke = _objc_msgForward;
        if(flags & BLOCK_USE_STRET) {
#if !defined(__arm64__)
            invoke = (IMP)_objc_msgForward_stret;
#endif
        }
    }
    return self;
}

- (void)dealloc
{
    if(!self.copyed) {
        [self performSelector:@selector(cleanup) onThread:self.thread withObject:@(self.blockID) waitUntilDone:YES];
    } else {
        
    }
}

- (void)cleanup:(NSInteger)blockID
{
    free_block(blockID);
}

- (NSMethodSignature *)methodSignatureForSelector: (SEL)sel
{
    const char *types = self.signature.UTF8String;
    NSMethodSignature *sig = [NSMethodSignature signatureWithObjCTypes: types];
    while([sig numberOfArguments] < 2)
    {
        types = [[NSString stringWithFormat: @"%s%s", types, @encode(void *)] UTF8String];
        sig = [NSMethodSignature signatureWithObjCTypes: types];
    }
    return sig;
}

- (void)forwardInvocation:(NSInvocation *)invocation
{
    forward_block_invocation(self.blockID, invocation);
}

- (id)copyWithZone:(NSZone *)zone
{
    DynamBlock *block = [DynamBlock allocWithZone:zone];
    block.copyed = YES;
    block.signature = self.signature;
    return block;
}

@end
