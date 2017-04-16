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

enum UITableViewCellStyle {
    UITableViewCellStyleDefault,	// Simple cell with text label and optional image view (behavior of UITableViewCell in iPhoneOS 2.x)
    UITableViewCellStyleValue1,		// Left aligned label on left and right aligned label on right with blue text (Used in Settings)
    UITableViewCellStyleValue2,		// Right aligned label on left with blue text and left aligned label on right (Used in Phone/Contacts)
    UITableViewCellStyleSubtitle	// Left aligned label on top and left aligned label on bottom with gray text (Used in iPod).
};

void NSLog(id format, ...);

const CGPoint CGPointZero;
const CGSize CGSizeZero;
const CGRect CGRectZero;
CGFloat CGRectGetMinX(CGRect rect);
CGFloat CGRectGetMidX(CGRect rect);
CGFloat CGRectGetMaxX(CGRect rect);
CGFloat CGRectGetMinY(CGRect rect);
CGFloat CGRectGetMidY(CGRect rect);
CGFloat CGRectGetMaxY(CGRect rect);
CGFloat CGRectGetWidth(CGRect rect);
CGFloat CGRectGetHeight(CGRect rect);

]]

local lib = ffi.C

local cocoa = {}

cocoa.CGPoint   = ffi.typeof("struct CGPoint")
cocoa.CGSize    = ffi.typeof("struct CGSize")
cocoa.CGRect    = ffi.typeof("struct CGRect")

cocoa.UITableViewCellStyle = ffi.typeof("enum UITableViewCellStyle")
cocoa.UITableViewCellStyleDefault = ffi.cast(cocoa.UITableViewCellStyle, 0)
cocoa.UITableViewCellStyleValue1 = ffi.cast(cocoa.UITableViewCellStyle, 1)
cocoa.UITableViewCellStyleValue2 = ffi.cast(cocoa.UITableViewCellStyle, 2)
cocoa.UITableViewCellStyleSubtitle = ffi.cast(cocoa.UITableViewCellStyle, 3)

cocoa.NSLog     = lib.NSLog
cocoa.CGPointZero = lib.CGPointZero
cocoa.CGSizeZero = lib.CGSizeZero
cocoa.CGRectZero = lib.CGRectZero
function cocoa.CGRectGetMinX(rect)
    return tonumber(lib.CGRectGetMinX(rect))
end
function cocoa.CGRectGetMidX(rect)
    return tonumber(lib.CGRectGetMidX(rect))
end
function cocoa.CGRectGetMaxX(rect)
    return tonumber(lib.CGRectGetMaxX(rect))
end
function cocoa.CGRectGetMinY(rect)
    return tonumber(lib.CGRectGetMinY(rect))
end
function cocoa.CGRectGetMidY(rect)
    return tonumber(lib.CGRectGetMidY(rect))
end
function cocoa.CGRectGetMaxY(rect)
    return tonumber(lib.CGRectGetMaxY(rect))
end
function cocoa.CGRectGetWidth(rect)
    return tonumber(lib.CGRectGetWidth(rect))
end
function cocoa.CGRectGetHeight(rect)
    return tonumber(lib.CGRectGetHeight(rect))
end

return cocoa
