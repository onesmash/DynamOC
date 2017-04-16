package.path = package.path .. ';' .. __scriptDirectory .. '/?.lua'
local ffi = require("ffi")
runtime = require('runtime')
dispatch = require('dispatch')
cocoa = require('cocoa')
