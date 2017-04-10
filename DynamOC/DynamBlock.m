//
//  DynamBlock.m
//  Pods
//
//  Created by Xuhui on 23/02/2017.
//
//

#import "DynamBlock.h"
#import "LuaContext+Private.h"
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

static void copy_block(DynamBlock *dst, const DynamBlock *src);
static void dispose_block(const void *block);

@interface DynamBlock () {
    id block_;
}

@property (nonatomic, weak) NSThread *createThread;
@property (nonatomic, assign) BOOL copyed;
@property (nonatomic, strong) NSData *codeDump;
@property (nonatomic, strong) NSArray *upvalueDump;

@end

@implementation DynamBlock

- (instancetype)initWithSignature:(NSString *)sig
{
    self = [self init];
    if(self) {
        self.createThread = [NSThread currentThread];
        self.copyed = NO;
        self.signature = sig;
        flags = BLOCK_IS_GLOBAL;
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
    }
    return self;
}

- (instancetype)initWithBlockID:(NSInteger)blockID signature:(NSString *)sig
{
    self = [self initWithSignature:sig];
    if(self) {
        self.blockID = blockID;
    }
    return self;
}

- (void)dealloc
{
    if(!self.copyed) {
        [self performSelector:@selector(cleanup:) onThread:self.createThread withObject:@(self.blockID) waitUntilDone:YES];
    } else {
        
    }
}

- (void)cleanup:(NSInteger)blockID
{
    free_block(blockID);
}

- (NSMethodSignature *)methodSignatureForSelector: (SEL)sel
{
    NSMethodSignature *sig = [super methodSignatureForSelector:sel];
    if(!sig) {
        const char *types = self.signature.UTF8String;
        sig = [NSMethodSignature signatureWithObjCTypes: types];
        while([sig numberOfArguments] < 2)
        {
            types = [[NSString stringWithFormat: @"%s%s", types, @encode(void *)] UTF8String];
            sig = [NSMethodSignature signatureWithObjCTypes: types];
        }
    }
    return sig;
}

- (void)forwardInvocation:(NSInvocation *)invocation
{
    if(self.copyed) {
        forward_block_code_invocation(self.codeDump, self.upvalueDump, invocation);
    } else {
        if([[NSThread currentThread] isEqual:self.createThread]) {
            forward_block_id_invocation(self.blockID, invocation);
        } else {
            if(!self.syncDispatch) {
                [self performSelector:@selector(dumpBlockTo:) onThread:self.createThread withObject:self waitUntilDone:YES];
                forward_block_code_invocation(self.codeDump, self.upvalueDump, invocation);
                CFRelease((__bridge CFTypeRef)(self));
            } else {
                push_luacontext(get_luacontext(self.createThread));
                forward_block_id_invocation(self.blockID, invocation);
                pop_luacontext();
            }
        }
    }
}

- (id)copyWithZone:(NSZone *)zone
{
    DynamBlock *block = [[DynamBlock allocWithZone:zone] initWithSignature:self.signature];
    if(!self.copyed) {
        [self performSelector:@selector(dumpBlockTo:) onThread:self.createThread withObject:self waitUntilDone:YES];
    }
    block.createThread = [NSThread currentThread];
    block.codeDump = self.codeDump;
    block.upvalueDump = self.upvalueDump;
    block.copyed = YES;
    return block;
}

- (void)dumpBlockTo:(DynamBlock *)block
{
    block.codeDump = [self dumpCode];
    block.upvalueDump = [self dumpUpvalue];
}

- (NSData *)dumpCode
{
    return dump_block_code(self.blockID);
}

- (NSArray *)dumpUpvalue
{
    return dump_block_upvalue(self.blockID);
}

@end
