local ffi = require("ffi")
local bit = require("bit")
local jit = require("jit")

local objc = {
    debug = false,
    relaxedSyntax = true, -- Allows you to omit trailing underscores when calling methods at the expense of some performance.
    fallbackOnMsgSend = true, -- Calls objc_msgSend if a method implementation is not found (This throws an exception on failure)
    frameworkSearchPaths = {
        "/System/Library/Frameworks/%s.framework/%s",
        "/Library/Frameworks/%s.framework/%s",
        "~/Library/Frameworks/%s.framework/%s"
    }
}

objc.ffi = ffi

local function _log(...)
    if objc.debug == true then
        local args = {...}
        for i=1, #args do
            args[i] = tostring(args[i])
        end
        io.stderr:write("[objc] "..table.concat(args, " ").."\n")
    end
end

if ffi.abi("64bit") then
    ffi.cdef([[
    typedef double CGFloat;
    typedef long NSInteger;
    typedef unsigned long NSUInteger;
    ]])
else
    ffi.cdef([[
    typedef float CGFloat;
    typedef int NSInteger;
    typedef unsigned int NSUInteger;
    ]])
end

ffi.cdef[[
typedef struct _NSRange {
    NSUInteger location;
    NSUInteger length;
} NSRange;
typedef struct objc_class *Class;
struct objc_class { Class isa; };
struct objc_object { Class isa; };
typedef struct objc_object *id;

typedef struct objc_selector *SEL;
typedef id (*IMP)(id, SEL, ...);
typedef signed char BOOL;
typedef struct objc_method *Method;
struct objc_method_description { SEL name; char *types; };
typedef struct objc_ivar *Ivar;

typedef struct {
    const char *name; 
    const char *value;
} objc_property_attribute_t;

id objc_msgSend(id theReceiver, SEL theSelector, ...);
void objc_msgSend_stret(id self, SEL op, ...);
Class objc_allocateClassPair(Class superclass, const char *name, size_t extraBytes);
void objc_registerClassPair(Class cls);
id _objc_msgForward(id receiver, SEL sel, ...);
void _objc_msgForward_stret(id receiver, SEL sel, ...);

Class objc_getClass(const char *name);
const char *class_getName(Class cls);
Method class_getClassMethod(Class aClass, SEL aSelector);
IMP class_getMethodImplementation(Class cls, SEL name);
Method class_getInstanceMethod(Class aClass, SEL aSelector);
Method class_getClassMethod(Class aClass, SEL aSelector);
BOOL class_respondsToSelector(Class cls, SEL sel);
Class class_getSuperclass(Class cls);
IMP class_replaceMethod(Class cls, SEL name, IMP imp, const char *types);
BOOL class_addMethod(Class cls, SEL name, IMP imp, const char *types);
BOOL class_addIvar(Class cls, const char *name, size_t size, uint8_t alignment, const char *types);
BOOL class_addProperty(Class cls, const char *name, const objc_property_attribute_t *attributes, unsigned int attributeCount);
id objc_getProperty(id self, SEL _cmd, ptrdiff_t offset, BOOL atomic);
void objc_setProperty(id self, SEL _cmd, ptrdiff_t offset, id newValue, BOOL atomic, signed char shouldCopy);
void objc_copyStruct(void *dest, const void *src, ptrdiff_t size, BOOL atomic, BOOL hasStrong);

Class object_getClass(id object);
const char *object_getClassName(id obj);
Ivar object_getInstanceVariable(id obj, const char *name, void **outValue);

SEL method_getName(Method method);
unsigned method_getNumberOfArguments(Method method);
void method_getReturnType(Method method, char *dst, size_t dst_len);
void method_getArgumentType(Method method, unsigned int index, char *dst, size_t dst_len);
IMP method_getImplementation(Method method);
const char *method_getTypeEncoding(Method method);
void method_exchangeImplementations(Method m1, Method m2);

const char * ivar_getTypeEncoding(Ivar ivar);
ptrdiff_t ivar_getOffset(Ivar ivar);

SEL sel_registerName(const char *str);
const char* sel_getName(SEL aSelector);

void free(void *ptr);

// Used to check if a file exists
int access(const char *path, int amode);

void forward_invocation(id target, SEL selector, id invocation);
id get_current_luacontext();
enum DynamUpvalueType {
    kDynamUpvalueTypeDouble,
    kDynamUpvalueTypeInteger,
    kDynamUpvalueTypeUInteger,
    kDynamUpvalueTypeBoolean,
    kDynamUpvalueTypeString,
    kDynamUpvalueTypeBytes,
    kDynamUpvalueTypeObject
};
]]

local C = ffi.C
objc.C = C

function objc.loadFramework(name, absolute)
    local canRead = bit.lshift(1,2)
    -- Check if it's an absolute path
    if absolute then
        local path = name
        local a,b, name = path:find("([^./]+).framework$")
        path = path..name
        if C.access(path, canRead) == 0 then
            bs.load(path)
        end
        return
    end

    -- Otherwise search
    for i,path in pairs(objc.frameworkSearchPaths) do
        path = path:format(name,name)
        if C.access(path, canRead) == 0 then
            return ffi.load(path, true)
        end
    end
    error("Error! Framework '"..name.."' not found.")
end

local function _release(obj)
    if objc.debug then
        _log("Releasing object of class", ffi.string(C.class_getName(obj:class())), ffi.cast("void*", obj), "Refcount: ", obj:retainCount())
    end
    obj:release()
end

setmetatable(objc, {
    __index = function(t, key)
        local ret = C.objc_getClass(key)
        if ret == nil then
            return nil
        end
        t[key] = ret
        return ret
    end
})

function objc.selToStr(sel)
    return ffi.string(ffi.C.sel_getName(sel))
end

ffi.metatype("struct objc_selector", { __tostring = objc.selToStr })

local SEL=function(str)
    return ffi.C.sel_registerName(str)
end
objc.SEL = SEL

-- Stores references to IMP(method) wrappers
local _classMethodCache = {}; objc.classMethodCache = _classMethodCache
local _instanceMethodCache = {}; objc.instanceMethodCache = _instanceMethodCache

local _classNameCache = setmetatable({}, { __mode = "k" })
-- We cache imp types both for performance, and so we don't fill the ffi type table with duplicates
local _impTypeCache = setmetatable({}, {__index=function(t,impSig)
    t[impSig] = ffi.typeof(impSig)
    return t[impSig]
end})
local _idType = ffi.typeof("struct objc_object*")
objc.idType = _idType
local _UINT_MAX
local _INT_MAX
if ffi.abi("64bit") then
    _UINT_MAX = 18446744073709551615ULL
    _INT_MAX = 9223372036854775807LL
else
    _UINT_MAX = 4294967295
    _INT_MAX = 2147483647
end


-- Parses an ObjC type encoding string into an array of type dictionaries
function objc.parseTypeEncoding(str)
    local fieldIdx = 1
    local fields = { { name = "", type = "", indirection = 0, isConst = false} }
    local depth = 0
    local inQuotes = false
    local curField = fields[1]
    
    local temp, c
    for i=1, #str do
        c = str:sub(i,i)
        if     c:find("^[{%(%[]") then depth = depth + 1
        elseif c:find("^[}%)%]]") then depth = depth - 1
        elseif c == '"' then inQuotes = not inQuotes;
        end
        
        if depth > 0 then
            curField.type = curField.type .. c
        elseif inQuotes == true and c ~= '"' then
            curField.name = curField.name .. c
        elseif c == "^" then curField.indirection = curField.indirection + 1
        elseif c == "r" then curField.isConst = true
        elseif c:find('^["nobNRVr%^%d]') == nil then -- Skip over type qualifiers and bitfields
            curField.type = curField.type .. c
            fieldIdx = fieldIdx + 1
            fields[fieldIdx] = { name = "", type = "", indirection = 0 } 
            curField = fields[fieldIdx]
        end
    end
    -- If the last field was blank, remove it
    if #fields[fieldIdx].name == 0 then
        table.remove(fields, fieldIdx)
    end
    return fields
end

-- Parses an array encoding like [5i]
local function _parseArrayEncoding(encoded)
    local unused, countEnd, count = encoded:find("%[([%d]+)")
    local unused, unused2, typeEnc = encoded:find("([^%d]+)%]")
    local type = objc.typeToCType(objc.parseTypeEncoding(typeEnc)[1])
    if type == nil then
        return nil
    end
    return type, count
end

-- Parses a struct/union encoding like {CGPoint="x"d"y"d}
local _definedStructs = setmetatable({}, { __mode = "kv" })
local function _parseStructOrUnionEncoding(encoded, isUnion)
    local pat = "{([^=}]+)[=}]"
    local keyword = "struct"
    if isUnion == true then
        pat = '%(([^=%)]+)[=%)]'
        keyword = "union"
    end

    local unused, nameEnd, name = encoded:find(pat)
    local typeEnc = encoded:sub(nameEnd+1, #encoded-1)
    local fields = objc.parseTypeEncoding(typeEnc, '"')

    if name == "?" then name = "" end -- ? means an anonymous struct/union

    if     #fields <= 1 and name == "" then return keyword.."{} "..name
    elseif #fields <= 1 then return keyword.." "..name end

    local typeStr = _definedStructs[name]
    -- If the struct has been defined already, or does not have field name information, just return the name
    if typeStr ~= nil then
        return keyword.." "..name
    end

    typeStr = keyword.." "..name.." { "
    for i,f in pairs(fields) do
        local name = f.name
        if #name == 0 then name = "field"..tostring(i) end

        local type = objc.typeToCType(f, name)
        if type == nil then
            if objc.debug == true then _log("Unsupported type in ", keyword, name, ": ", f.type) end
            return nil
        end
        typeStr = typeStr .. type ..";"
    end
    typeStr = typeStr .." }"

    -- If the struct has a name we create a ctype and then just return the name for it. If it has none, we return the definition
    if #name > 0 then
        _definedStructs[name] = typeStr
        -- We need to wrap the def in a pcall so that we don't crash in case the struct is too big (As is the case with one in IOKit)
        local success, err = pcall(ffi.cdef, typeStr)
        if success == false then
            _log("Error loading struct ", name, ": ", err)
        end
        return keyword.." "..name
    else
        return typeStr
    end
end

local CGFloatEncode
local NSIntegerEncode
local NSUIntegerEncode
if ffi.abi("64bit") then
    CGFloatEncode = "d"
    NSIntegerEncode = "q"
    NSUIntegerEncode = "Q"
else
    CGFloatEncode = "f"
    NSIntegerEncode = "l"
    NSUIntegerEncode = "L"
end
local CGPointEncode = "{CGPoint="..CGFloatEncode..CGFloatEncode.."}"
local CGSizeEncode = "{CGSize="..CGFloatEncode..CGFloatEncode.."}"
local CGRectEncode = "{CGRect="..CGPointEncode..CGSizeEncode.."}"
local UIEdgeInsetsEncode = "{UIEdgeInsets="..CGFloatEncode..CGFloatEncode..CGFloatEncode..CGFloatEncode.."}"

objc.encode = {["CGFloat"] = CGFloatEncode, ["NSInteger"] = NSIntegerEncode, 
                ["NSUInteger"] = NSUIntegerEncode, ["CGPoint"] = CGPointEncode,
                ["CGSize"] = CGSizeEncode, ["UIEdgeInsets"] = UIEdgeInsetsEncode }

-- Takes a type table (contains type info for a single type, obtained using parseTypeEncoding), and converts it to a  c signature
-- The optional second argument specifies whether or not 
local _typeEncodings = {
    ["@"] = "id", ["#"] = "Class", ["c"] = "char", ["C"] = "unsigned char",
    ["s"] = "short", ["S"] = "unsigned short", ["i"] = "int", ["I"] = "unsigned int",
    ["l"] = "long", ["L"] = "unsigned long", ["q"] = "long long", ["Q"] = "unsigned long long",
    ["f"] = "float", ["d"] = "double", ["B"] = "BOOL", ["v"] = "void", ["^"] = "void *", ["?"] = "void *",
    ["*"] = "char *", [":"] = "SEL", ["?"] = "void", ["{"] = "struct", ["("] = "union", ["["] = "array"
}
function objc.typeToCType(type, varName)
    varName = varName or ""
    local ret = ""
    local encoding = type.type
    local ptrStr = ("*"):rep(type.indirection)

    -- Then type encodings
    local typeStr = _typeEncodings[encoding:sub(1,1)]

    if typeStr == nil then
        _log("Error! type encoding '", encoding, "' is not supported")
        return nil
    elseif typeStr == "union" then
        local unionType = _parseStructOrUnionEncoding(encoding, true)
        if unionType == nil then
            _log("Error! type encoding '", encoding, "' is not supported")
            return nil
        end
        ret = string.format("%s %s %s%s", ret, unionType, ptrStr, varName)
    elseif typeStr == "struct" then
        local structType = _parseStructOrUnionEncoding(encoding, false)
        if structType == nil then
            _log("Error! type encoding '", encoding, "' is not supported")
            return nil
        end
        ret = string.format("%s %s %s%s", ret, structType, ptrStr, varName)
    elseif typeStr == "array" then
        local arrType, arrCount = _parseArrayEncoding(encoding)
        if arrType == nil then
            _log("Error! type encoding '", encoding, "' is not supported")
            return nil
        end
        ret = string.format("%s %s%s[%d]", arrType, ptrStr, varName, arrCount)
    else
        ret = string.format("%s %s %s%s", ret, typeStr, ptrStr, varName)
    end

    return ret
end
-- Creates a C function signature string for the given types
function objc.impSignatureForTypeEncoding(signature, name)
    name = name or "*" -- Default to an anonymous function pointer
    signature = signature or "v"
    
    local types = objc.parseTypeEncoding(signature)
    if types == nil or #types == 0 then
        return nil
    end
    local signature = objc.typeToCType(types[1]).." ("..name..")("

    for i=2,#types do
        local type = objc.typeToCType(types[i], "p"..(i-1))

        if type == nil then
            return nil
        end
        if i < #types then
            type = type..","
        end
        signature = signature..type
    end

    return signature..")"
end

-- Returns the IMP of a method correctly typecast
function objc.impForMethod(method)
    local typeEncoding = ffi.string(C.method_getTypeEncoding(method))
    local impSignature = objc.impSignatureForTypeEncoding(typeEncoding)
    if impSignature == nil then
        return nil
    end
    if objc.debug then _log("Reading method:", objc.selToStr(C.method_getName(method)), typeEncoding, impSignature) end
    return ffi.cast(_impTypeCache[impSignature], C.method_getImplementation(method))
end

-- Convenience functions

function objc.objToStr(aObj) -- Automatically called by tostring(object)
    if aObj == nil then
        return "nil"
    end
    return ffi.string(aObj:description():UTF8String())
end

-- Converts a lua type to an objc object
function objc.Obj(v)
    if type(v) == "number" then
        return objc.NSNum(v)
    elseif type(v) == "string" then
        return objc.NSStr(v)
    elseif type(v) == "table" then
        if #v == 0 then
            return objc.NSDic(v)
        else
            return objc.NSArr(v)
        end
    elseif type(v) == "cdata" then
        return ffi.cast(_idType, v)
    end
    return nil
end
function objc.NSStr(aStr)
    return objc.NSString:stringWithUTF8String_(ffi.cast("char*", aStr))
end
function objc.NSNum(aNum)
    return objc.NSNumber:numberWithDouble(aNum)
end
function objc.NSArr(aTable)
    local ret = objc.NSMutableArray:array()
    for i,v in ipairs(aTable) do
        ret:addObject(objc.Obj(v))
    end
    return ret
end
function objc.NSDic(aTable)
    local ret = objc.NSMutableDictionary:dictionary()
    for k,v in pairs(aTable) do
        ret:setObject_forKey(objc.Obj(v), objc.Obj(k))
    end
    return ret
end

local _tonumber = tonumber
local _doubleValSel = SEL("doubleValue")
tonumber = function(val, ...)
    if type(val) == "cdata" and ffi.istype(_idType, val) and val:respondsToSelector(_doubleValSel) then
        return val:doubleValue()
    end
    return _tonumber(val, ...)
end

-- Method calls

-- Takes a selector string (with colons replaced by underscores) and returns the number of arguments)
function _argCountForSelArg(selArg)
    local counting = false
    local count = 0
    for i=1,#selArg do
        if counting == false then
            counting = (selArg:sub(i,i) ~= "_")
        elseif selArg:sub(i,i) == "_" then
            count = count + 1
        end
    end
    return count
end

-- Replaces all underscores except the ones at the beginning of the string by colons
function _selectorFromSelArg(selArg)
    local replacing = false
    local count = 0
    for i=1,#selArg do
        if replacing == false then
            replacing = (selArg:sub(i,i) ~= "_")
        elseif selArg:sub(i,i) == "_" then
            selArg = table.concat{selArg:sub(1,i-1), ":", selArg:sub(i+1)}
        end
    end
    return selArg
end

-- Used as a __newindex metamethod
local function _setter(self, key, value)
    -- TODO 所有的ivar都是用property实现
    local selector = "set"..key:sub(1,1):upper()..key:sub(2)
    if C.class_respondsToSelector(C.object_getClass(self), SEL(selector..":")) == 1 then
        return self[selector](self, value)
    elseif objc.fallbackOnMsgSend == true then
        return self:setValue_forKey_(Obj(value), NSStr(key))
    else
        print("[objc] Key "..key.." not found")
    end
end

-- just an ugly getter to make it nicer to work with arrays in the repl. (Don't use this in your actual code please,
-- I'll remove it when a better way presents itself)
local function _getter(self, key)
    local idx = tonumber(key)
    if idx ~= nil then
        return self:objectAtIndex(idx)
    else
        if C.class_respondsToSelector(C.object_getClass(self), SEL(key)) == 1 then
            return self[key](self)
        elseif objc.fallbackOnMsgSend == true then
            return self:valueForKey_(NSStr(key))
        else
            print("[objc] Key "..key.." not found")
        end
    end
end

local _emptyTable = {} -- Keep an empty table around so we don't have to create a new one every time a method is called
ffi.metatype("struct objc_class", {
    __call = function(self)
        error("[objc] Classes are not callable\n"..debug.traceback())
    end,
    __tostring = objc.objToStr,
    __index = function(realSelf,selArg)
        return function(self, ...)
            if self ~= realSelf then
                error("[objc] Self not passed. You probably used dot instead of colon syntax\n"..debug.traceback())
                return nil
            end

            if objc.relaxedSyntax == true then
                -- Append missing underscores to the selector
                selArg = selArg .. ("_"):rep(select("#", ...) - _argCountForSelArg(selArg))
            end

            -- First try the cache
            local cached = (_classMethodCache[_classNameCache[self]] or _emptyTable)[selArg]
            if cached ~= nil then
                return cached(self, ...)
            end

            -- Else, load the method
            local selStr = _selectorFromSelArg(selArg)

            local imp
            local methodDesc = C.class_getClassMethod(self, SEL(selStr))
            if methodDesc ~= nil then
                imp = objc.impForMethod(methodDesc)
            elseif objc.fallbackOnMsgSend == true then
                -- TODO
                imp = C.objc_msgSend
                if jit.arch ~= "arm64" then
                    if string.sub(typeEncoding, 1, 1) == "{" then
                        local signature = self:methodSignatureForSelector(SEL(selStr))
                        local range = signature.debugDescription:rangeOfString_(objc.NSStr("is special struct return? YES"))
                        if range.location ~= _INT_MAX then
                            imp = C.objc_msgSend_stret
                        end
                    end
                end
            else
                print("[objc] Method "..selStr.." not found")
                return nil
            end

            -- Cache the calling block and execute it
            _classNameCache[self] = _classNameCache[self] or ffi.string(C.class_getName(self))
            local className = _classNameCache[self]
            _classMethodCache[className] = _classMethodCache[className] or {}
            _classMethodCache[className][selArg] = function(receiver, ...)
                local success, ret = pcall(imp, ffi.cast(_idType, receiver), SEL(selStr), ...)
                if success == false then
                    error(ret.."\n"..debug.traceback())
                end

                if ffi.istype(_idType, ret) and ret ~= nil then
                    _classNameCache[ret] = className
                    if (selStr:sub(1,5) ~= "alloc" and selStr ~= "new")  then
                        if objc.debug then
                            _log("Retaining object of class (sel:"..selStr..")", ffi.string(C.class_getName(ret:class())), ffi.cast("void*", ret))
                        end
                        ret = ret:retain()
                    end
                    if selStr:sub(1,5) ~= "alloc" then
                        ret = ffi.gc(ret, _release)
                    end
                end
                return ret
            end
            return _classMethodCache[className][selArg](self, ...)
        end
    end,
    __newindex = _setter
})

-- Returns a function that takes an object reference and the arguments to pass to the method.
function objc.getInstanceMethodCaller(realSelf,selArg)
    return function(self, ...)
        if self ~= realSelf then
            error("[objc] Self not passed. You probably used dot instead of colon syntax")
            return nil
        end

        -- First try the cache
        if objc.relaxedSyntax == true then
            -- Append missing underscores to the selector
            selArg = selArg .. ("_"):rep(select("#", ...) - _argCountForSelArg(selArg))
        end

        local cached = (_instanceMethodCache[_classNameCache[self]] or _emptyTable)[selArg]
        if cached ~= nil then
            return cached(self, ...)
        end

        -- Else, load the method
        local selStr = _selectorFromSelArg(selArg)

        local imp
        local methodDesc = C.class_getInstanceMethod(C.object_getClass(self), SEL(selStr))
        if methodDesc ~= nil then
            imp = objc.impForMethod(methodDesc)
        elseif objc.fallbackOnMsgSend == true then
            -- TODO
            imp = C.objc_msgSend
            if jit.arch ~= "arm64" then
                if string.sub(typeEncoding, 1, 1) == "{" then
                    local signature = self:methodSignatureForSelector(SEL(selStr))
                    local range = signature.debugDescription:rangeOfString_(objc.NSStr("is special struct return? YES"))
                    if range.location ~= _INT_MAX then
                        imp = C.objc_msgSend_stret
                    end
                end
            end
        else
            print("[objc] Method "..selStr.." not found")
            return nil
        end

        -- Cache the calling block and execute it
        _classNameCache[self] = _classNameCache[self] or ffi.string(C.object_getClassName(self))
        local className = _classNameCache[self]
        _instanceMethodCache[className] = _instanceMethodCache[className] or {}
        _instanceMethodCache[className][selArg] = function(receiver, ...)
            local success, ret = pcall(imp, receiver, SEL(selStr), ...)
            if success == false then
                error("Error calling '"..selStr.."': "..ret.."\n"..debug.traceback())
            end

            if ffi.istype(_idType, ret) and ret ~= nil and not (selStr == "retain" or selStr == "release") then
                _classNameCache[ret] = ffi.string(C.object_getClassName(ret))
                if not (selStr:sub(1,4) == "init" or selStr:sub(1,4) == "copy" or selStr:sub(1,11) == "mutableCopy") then
                    if objc.debug then
                        _log("Retaining object of class (sel:"..selStr..")", ffi.string(C.class_getName(ret:class())), ffi.cast("void*", ret))
                    end
                    ret = ret:retain()
                end
                ret = ffi.gc(ret, _release)
            end
            return ret
        end
        return _instanceMethodCache[className][selArg](self, ...)
    end
end

ffi.metatype("struct objc_object", {
    __call = _getter, -- Called using aObject[[key]], it's ugly, may be removed and should probably only be used when debugging in the repl
    __tostring = objc.objToStr,
    __index = objc.getInstanceMethodCaller,
    __newindex = _setter
})

--
-- Introspection and class extension

local function _getIvarInfo(instance, ivarName)
    local ivar = C.object_getInstanceVariable(instance, ivarName, nil)
    if ivar == nil then
        return nil
    end
    local typeEnc = ffi.string(C.ivar_getTypeEncoding(ivar))
    local typeArr = objc.parseTypeEncoding(typeEnc)
    if typeArr == nil or #typeArr ~= 1 then
        return nil
    end
    local cType = objc.typeToCType(typeArr[1])
    if cType == nil then
        return nil
    end
    local offset = C.ivar_getOffset(ivar)
    return ivar, offset, typeEnc, cType
end

objc.getIvarInfo = _getIvarInfo

function addProperty(class, name, attributes)
    local count = 3
    for _ in pairs(attributes) do count = count + 1 end
    local cType = "objc_property_attribute_t[" .. count .. "]"
    local attrs = ffi.new(cType, {})
    local index = 0;
    attrs[index].name = "T"
    attrs[index].value = attributes["typeEncoding"]
    index = index + 1
    if attributes["readOnly"] then
        attrs[index].name = "R"
        attrs[index].value = ""
        index = index + 1
    end
    if attributes["ownerShip"] then
        local ownerShip = attributes["ownerShip"]
        if ownerShip == "strong" then
            attrs[index].name = "&"
            attrs[index].value = ""
            index = index + 1
        elseif ownerShip == "weak" then
            attrs[index].name = "W"
            attrs[index].value = ""
            index = index + 1
        elseif ownerShip == "copy" then
            attrs[index].name = "C"
            attrs[index].value = ""
            index = index + 1
        end
    end
    if attributes["nonatomic"] then
        attrs[index].name = "N"
        attrs[index].value = ""
        index = index + 1
    end
    local setter = "set"..name:sub(1,1):upper()..name:sub(2)..":"
    if attributes["setterName"] then
        attrs[index].name = "S"
        attrs[index].value = attributes["setterName"]
        index = index + 1
    else
        attrs[index].name = "S"
        attrs[index].value = setter
        local ivarName = attributes["ivarName"] or "_"..name
        local shouldCopy = attributes["ownerShip"] == "copy"
        local nonatomic = attributes["nonatomic"] == true 
        objc.addMethod(class, SEL(setter), function(self, cmd, value)
            if type(value) == "cdata" then
                local ivar, offset, typeEnc, cType = runtime.getIvarInfo(self, ivarName)
                if ivar then
                    if runtime.ffi.istype(runtime.idType, value) then
                        runtime.ffi.C.objc_setProperty(self, cmd, offset, value, not nonatomic, shouldCopy or value:isKindOfClass(objc.NSBlock))
                    else 
                        local src = runtime.ffi.cast(cType.."*", value)
                        local dst = runtime.ffi.cast(cType.."*", self + offset)
                        runtime.ffi.C.objc_copyStruct(dst, src, runtime.ffi.sizeof(value), not nonatomic, false)
                    end
                end
            end
        end, "v@:"..attributes["typeEncoding"])
        index = index + 1
    end
    if attributes["getterName"] then
        attrs[index].name = "G"
        attrs[index].value = attributes["getterName"]
        index = index + 1
    else 
        attrs[index].name = "G"
        attrs[index].value = name
        local ivarName = attributes["ivarName"] or "_"..name 
        local nonatomic = attributes["nonatomic"] == true
        objc.addMethod(class, SEL(name), function(self, cmd)
            local _, offset, typeEnc, cType = runtime.getIvarInfo(self, ivarName)
            if runtime.ffi.typeof(cType) == runtime.idType then
                return runtime.C.objc_getProperty(self, cmd, offset, not nonatomic)
            else 
                local src = runtime.ffi.cast(cType.."*", self + offset)
                local dst = runtime.ffi.new(cType.."[1]")
                local ffiType = runtime.ffi.typeof(cType)
                runtime.C.objc_copyStruct(dst, src, runtime.ffi.sizeof(ffiType), not nonatomic, false)
                return dst[0]
            end
        end, attributes["typeEncoding"].."@:")
        index = index + 1
    end
    local ivarName = "_"..name
    if attributes["ivarName"] then
        attrs[index].name = "V"
        attrs[index].value = attributes["ivarName"]
    else
        local ivar, offset, typeEnc, cType = _getIvarInfo(self, ivarName)
        if ivar == nil then
            local typeArr = objc.parseTypeEncoding(attributes["typeEncoding"])
            if typeArr ~= nil and #typeArr == 1 then
                local cType = objc.typeToCType(typeArr[1])
                if cType ~= nil then
                    local ffiType = ffi.typeof(cType)
                    local size = ffi.sizeof(ffiType)
                    local alignment = ffi.alignof(ffiType)
                    C.class_addIvar(class, ivarName, size, alignment, attributes["typeEncoding"])
                end
            end
        end
    end
    C.class_addProperty(class, name, attrs, count)
end

-- Creates and returns a new subclass of superclass (or if superclass is nil, a new root class)
-- ivars argument is an optional table of ivars, keyed by name with values containing the type encoding for the var
function objc.createClass(superclass, className, ivars, properties)
    ivars = ivars or {}
    local class = C.objc_allocateClassPair(superclass, className, 0)

    for name, typeEnc in pairs(ivars) do
        -- Parse the type and get the size
        local typeArr = objc.parseTypeEncoding(typeEnc)
        if typeArr ~= nil and #typeArr == 1 then
            local cType = objc.typeToCType(typeArr[1])
            if cType ~= nil then
                local ffiType = ffi.typeof(cType)
                local size = ffi.sizeof(ffiType)
                local alignment = ffi.alignof(ffiType)
                C.class_addIvar(class, name, size, alignment, typeEnc)
            end
        end
    end

    for name, attributes in pairs(properties) do
        addProperty(class, name, attributes)
    end

    C.objc_registerClassPair(class)
    return class
end

-- Calls the superclass's implementation of a method
function objc.callSuper(self, selector, ...)
    local superClass = C.class_getSuperclass(C.object_getClass(self))
    local method = C.class_getInstanceMethod(superClass, selector)
    return objc.impForMethod(method)(self, selector, ...)
end

-- Swaps two methods of a class (They must have the same type signature)
function objc.swizzle(class, origSel, newSel)
    local origMethod = C.class_getInstanceMethod(class, origSel)
    local newMethod = C.class_getInstanceMethod(class, newSel)
    if C.class_addMethod(class, origSel, C.method_getImplementation(newMethod), C.method_getTypeEncoding(newMethod)) == true then
        C.class_replaceMethod(class, newSel, C.method_getImplementation(origMethod), C.method_getTypeEncoding(origMethod));
    else
        C.method_exchangeImplementations(origMethod, newMethod)
    end
end

local upvalueType = ffi.typeof("enum DynamUpvalueType")
local NSInteger = ffi.typeof("NSInteger")
local NSUInteger = ffi.typeof("NSUInteger")

function ctype(value)
    return string.sub(tostring(objc.ffi.typeof(value)), 7, -2)
end

function dumpLambdaUpvalues(lambda, upvalues)
    local i = 1
    while true do
        local name, value = debug.getupvalue(lambda, i)
        if not name then
            break
        end
        local upvalue = objc.DynamUpvalue:alloc():init()
        upvalue:setIndex(i)
        upvalue:setName(objc.Obj(name))
        if type(value) == "cdata" then
            if ffi.istype(_idType, value) then
                upvalue:setValue(value)
                upvalue:setType(upvalueType("kDynamUpvalueTypeObject"))
            elseif ffi.istype(NSInteger, value) then
                upvalue:setValue(objc.NSNumber:alloc():initWithInteger(value))
                upvalue:setType(upvalueType("kDynamUpvalueTypeInteger"))
            elseif ffi.istype(NSUInteger, value) then
                upvalue:setValue(objc.NSNumber:alloc():initWithUnsignedInteger(value))
                upvalue:setType(upvalueType("kDynamUpvalueTypeUInteger"))
            else
                local data = objc.NSData:dataWithBytes_length(value, ffi.sizeof(value))
                upvalue:setValue(data)
                upvalue:setCType(objc.Obj(ctype(value)))
                upvalue:setType(upvalueType("kDynamUpvalueTypeBytes"))
            end
        elseif type(value) == "boolean" then
            upvalue:setValue(objc.NSNumber:alloc():initWithBool(value))
            upvalue:setType(upvalueType("kDynamUpvalueTypeBoolean"))
        elseif type(value) == "number" then
            upvalue:setValue(objc.Obj(value))
            upvalue:setType(upvalueType("kDynamUpvalueTypeDouble"))
        elseif type(value) == "string" then
            upvalue:setValue(objc.Obj(value))
            upvalue:setType(upvalueType("kDynamUpvalueTypeString"))
        end
        upvalues:addObject(upvalue)
        i = i + 1
    end
end

-- Adds a function as a method to the given class
-- If the method already exists, it is renamed to __{selector}
-- The function must have self (id), and selector (SEL) as it's first two arguments
-- Defaults are to return void and to take an object and a selector
function objc.addMethod(class, selector, lambda, typeEncoding)
    local msgForwardIMP = C._objc_msgForward
    if jit.arch ~= "arm64" then
        if string.sub(typeEncoding, 1, 1) == "{" then
            local signature = objc.NSMethodSignature:signatureWithObjCTypes(typeEncoding)
            local range = signature.debugDescription:rangeOfString_(objc.NSStr("is special struct return? YES"))
            if range.location ~= _INT_MAX then
                msgForwardIMP = C._objc_msgForward_stret
            end
        end
    end

    local forwardInvocationSel = objc.SEL("forwardInvocation:")
    local renamedForwardInvocationSel = objc.SEL("__forwardInvocation:")
    if C.class_getMethodImplementation(class, forwardInvocationSel) ~= ffi.cast("IMP", C.forward_invocation) then
        if C.class_addMethod(class, renamedForwardInvocationSel, ffi.cast("IMP", C.forward_invocation), "v@:@") == 1 then
            objc.swizzle(class, forwardInvocationSel, renamedForwardInvocationSel)
        else 
            error("Couldn't replace forwardInvocation:")
        end
    end

    local originalIMP
    if C.class_respondsToSelector(class, selector) then
        originalIMP = C.class_getMethodImplementation(class, selector)
    end
    local renamedSel = objc.SEL("__"..objc.selToStr(selector))
    if C.class_respondsToSelector(class, renamedSel) == false then
        C.class_addMethod(class, renamedSel, originalIMP, typeEncoding)
    end

    -- TODO 序列化lambda
    local code = string.dump(lambda)
    local codeData = objc.NSData:dataWithBytes_length_(ffi.cast("void *", code), string.len(code))
    local upvalues = objc.NSMutableArray:array()
    dumpLambdaUpvalues(lambda, upvalues)
    local dynamMethod = objc.DynamMethod:alloc():initWithCode_upvalues(codeData, upvalues)
    class:__setLuaLambda_forKey_(dynamMethod, objc.Obj(objc.selToStr(selector)))

    C.class_replaceMethod(class, selector, msgForwardIMP, typeEncoding)
end

-- Gets the value of an ivar
function objc.getIvar(instance, ivarName)
    local ivar, offset, typeEnc, cType  = _getIvarInfo(instance, ivarName)
    if ivar == nil then
        return nil
    end
    local ptr = ffi.cast(cType.."*", instance+offset)
    return ptr[0]
end

-- Sets the value of an ivar
function objc.setIvar(instance, ivarName, value)
    local ivar, offset, typeEnc, cType  = _getIvarInfo(instance, ivarName)
    if ivar == nil then
        return nil
    end
    local ptr = ffi.cast(cType.."*", instance+offset)
    ptr[0] = value
end

function objc.weak(obj)
    if type(obj) == "cdata" and ffi.istype(_idType, obj) then
        return objc.WeakObject:alloc():initWithObject(obj)
    else
        return obj
    end
end

function objc.strong(obj)
    if type(obj) == "cdata" and ffi.istype(_idType, obj) then
        if obj:isKindOfClass(objc.WeakObject) then
            return obj:object()
        end
    else
        return obj
    end
end

function objc.createBlock(lambda, typeEncoding)
    local id = objc.registerLambda(lambda)
    local block = objc.DynamBlock:alloc():initWithBlockID_signature_(id, objc.Obj(typeEncoding))
    return block
end

function objc.dumpBlockUpvalues(lambda)
    local context = C.get_current_luacontext()
    local upvalues = context:returnRegister()
    dumpLambdaUpvalues(lambda, upvalues)
end

function objc.evaluateBlock(lambda)
    local context = C.get_current_luacontext()
    local invocation = context:argumentRegister()
    local methodSignature = invocation:methodSignature()
    local numberOfArguments = tonumber(methodSignature:numberOfArguments())
    local arguments = {}
    for i = 1, numberOfArguments - 1 do
        local argumentType = ffi.string(methodSignature:getArgumentTypeAtIndex_(i))
        local typeArr = objc.parseTypeEncoding(argumentType)
        if typeArr ~= nil and #typeArr == 1 then
            local cType = objc.typeToCType(typeArr[1])
            if cType ~= nil then
                cType = cType .. "[1]";
                local arg = ffi.new(cType)
                invocation:getArgument_atIndex_(arg, i)
                table.insert(arguments, arg[0])
            end
        end
    end
    local returnType = ffi.string(methodSignature:methodReturnType())
    local typeArr = objc.parseTypeEncoding(returnType)
    if typeArr ~= nil and #typeArr == 1 then
        local cType = objc.typeToCType(typeArr[1])
        if cType ~= nil then
            local ret = lambda(unpack(arguments))
            if returnType ~= "v" then
                cType = cType .. "[1]"
                local ret = ffi.new(cType, {ret})
                invocation:setReturnValue_(ret)
            end
        end
    end
end

function setLambdaUpvalues(lambda, upvalues)
    for i = 0, tonumber(upvalues:count()) - 1 do
        local upvalue = upvalues:objectAtIndex(i)
        if upvalue:type() == upvalueType("kDynamUpvalueTypeObject") then
            local value = upvalue:value();
            value:retain()
            ffi.gc(value, _release)
            debug.setupvalue(lambda, tonumber(upvalue:index()), value)
        elseif upvalue:type() == upvalueType("kDynamUpvalueTypeDouble") then
            debug.setupvalue(lambda, tonumber(upvalue:index()), tonumber(upvalue:value():doubleValue()))
        elseif upvalue:type() == upvalueType("kDynamUpvalueTypeInteger") then
            debug.setupvalue(lambda, tonumber(upvalue:index()), upvalue:value():integerValue())
        elseif upvalue:type() == upvalueType("kDynamUpvalueTypeUInteger") then
            debug.setupvalue(lambda, tonumber(upvalue:index()), upvalue:value():unsignedIntegerValue())
        elseif upvalue:type() == upvalueType("kDynamUpvalueTypeBoolean") then
            debug.setupvalue(lambda, tonumber(upvalue:index()), upvalue:value():boolValue())
        elseif upvalue:type() == upvalueType("kDynamUpvalueTypeString") then
            debug.setupvalue(lambda, tonumber(upvalue:index()), ffi.string(upvalue:value():UTF8String()))
        elseif upvalue:type() == upvalueType("kDynamUpvalueTypeBytes") then
            local data = ffi.new(ffi.string(upvalue:cType():UTF8String()))
            ffi.copy(data, upvalue:value():bytes(), tonumber(upvalue:value():length()))
            debug.setupvalue(lambda, tonumber(upvalue:index()), data)
        end
    end
end

function objc.evaluateBlockCode(codeData, len)
    local context = C.get_current_luacontext()
    local upvalues = context:argumentRegister():objectAtIndex(0)
    local invocation = context:argumentRegister():objectAtIndex(1)
    local methodSignature = invocation:methodSignature()
    local numberOfArguments = tonumber(methodSignature:numberOfArguments())
    local arguments = {}
    for i = 1, numberOfArguments - 1 do
        local argumentType = ffi.string(methodSignature:getArgumentTypeAtIndex_(i))
        local typeArr = objc.parseTypeEncoding(argumentType)
        if typeArr ~= nil and #typeArr == 1 then
            local cType = objc.typeToCType(typeArr[1])
            if cType ~= nil then
                cType = cType .. "[1]";
                local arg = ffi.new(cType)
                invocation:getArgument_atIndex_(arg, i)
                table.insert(arguments, arg[0])
            end
        end
    end
    local returnType = ffi.string(methodSignature:methodReturnType())
    local typeArr = objc.parseTypeEncoding(returnType)
    if typeArr ~= nil and #typeArr == 1 then
        local cType = objc.typeToCType(typeArr[1])
        if cType ~= nil then
            local lambda = loadstring(ffi.string(codeData, len))
            setLambdaUpvalues(lambda, upvalues)
            local ret = lambda(unpack(arguments))
            if returnType ~= "v" then
                cType = cType .. "[1]"
                local ret = ffi.new(cType, {ret})
                invocation:setReturnValue_(ret)
            end
        end
    end
end

function objc.evaluateMethod(codeData, len)
    local context = C.get_current_luacontext()
    local upvalues = context:argumentRegister():objectAtIndex(0)
    local invocation = context:argumentRegister():objectAtIndex(1)
    local methodSignature = invocation:methodSignature()
    local numberOfArguments = tonumber(methodSignature:numberOfArguments())
    local arguments = {invocation:target(), invocation:selector()}
    for i = 2, numberOfArguments - 1 do
        local argumentType = ffi.string(methodSignature:getArgumentTypeAtIndex_(i))
        local typeArr = objc.parseTypeEncoding(argumentType)
        if typeArr ~= nil and #typeArr == 1 then
            local cType = objc.typeToCType(typeArr[1])
            if cType ~= nil then
                cType = cType .. "[1]";
                local arg = ffi.new(cType)
                invocation:getArgument_atIndex_(arg, i)
                table.insert(arguments, arg[0])
            end
        end
    end
    local returnType = ffi.string(methodSignature:methodReturnType())
    local typeArr = objc.parseTypeEncoding(returnType)
    if typeArr ~= nil and #typeArr == 1 then
        local cType = objc.typeToCType(typeArr[1])
        if cType ~= nil then
            
            local lambda = loadstring(ffi.string(codeData, len))
            setLambdaUpvalues(lambda, upvalues)
            local ret = lambda(unpack(arguments))
            if returnType ~= "v" then
                cType = cType .. "[1]"
                local ret = ffi.new(cType, {ret})
                invocation:setReturnValue_(ret)
            end
        end
    end
end

return objc;
