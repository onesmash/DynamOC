package.path = package.path .. ';' .. __scriptDirectory .. '/?.lua'
runtime = require('runtime')

runtime.ffi.cdef[[
struct Test {int x;};
]]
