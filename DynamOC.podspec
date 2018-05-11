Pod::Spec.new do |s|
  s.name         = "DynamOC"
  s.version      = "1.1.9"
  s.summary      = "iOS hotfix using lua"
  s.homepage     = "https://github.com/onesmash/DynamOC"
  s.license      = { :type => 'MIT', :file => 'LICENSE' }
  s.author       = { "xuhui" => "good122000@qq.com" }
  s.ios.deployment_target = "8.0"
  s.source       = { :git => "https://github.com/onesmash/DynamOC.git", :tag => "#{s.version}", :submodules => true }
  s.source_files  = "DynamOC", "DynamOC/**/*.{h,m}"
  s.exclude_files = "DynamOC/boot32.h", "DynamOC/boot64.h", "DynamOC/runtime32.h", "DynamOC/runtime64.h", "DynamOC/cocoa32.h", "DynamOC/cocoa64.h", "DynamOC/dispatch32.h", "DynamOC/dispatch64.h"
  s.public_header_files = "DynamOC/LuaContext.h"
  s.resource_bundles = {
    'DynamOC' => ['DynamOC/runtime.lua', 'DynamOC/boot.lua', 'DynamOC/dispatch.lua', 'DynamOC/cocoa.lua']
  }
  s.libraries   = "luajit", "c++"
  s.dependency "LuaJIT-DynamOC", "~> 1.0.0"

end
