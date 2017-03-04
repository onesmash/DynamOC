local ffi = runtime.ffi

ffi.cdef[[

struct CGSize {
    CGFloat width;
    CGFloat height;
};
typedef struct CGSize CGSize;

struct CGPoint {
    CGFloat x;
    CGFloat y;
};

typedef struct CGPoint CGPoint;
struct CGRect {
    CGPoint origin;
    CGSize size;
};
typedef struct CGRect CGRect;

void NSLog(id format, ...);

]]

local lib = ffi.C

local cocoa = {}

cocoa.CGPoint   = ffi.typeof("struct CGPoint")
cocoa.CGSize    = ffi.typeof("struct CGSize")
cocoa.CGRect    = ffi.typeof("struct CGRect")

cocoa.NSLog     = lib.NSLog

return cocoa
