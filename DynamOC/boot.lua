local ffi = require("ffi")
if ffi.abi("64bit") then
    package.path = package.path .. ';' .. __scriptDirectory .. '/?@64.luac'
else
    package.path = package.path .. ';' .. __scriptDirectory .. '/?@32.luac'
end
runtime = require('runtime')
dispatch = require('dispatch')
cocoa = require('cocoa')
