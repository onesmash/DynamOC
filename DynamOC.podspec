Pod::Spec.new do |s|
  s.name         = "DynamOC"
  s.version      = "0.1.1"
  s.summary      = "A short description of DynamOC"
  s.homepage     = "https://github.com/onesmash/DynamOC"
  s.license      = { :type => 'MIT', :file => 'LICENSE' }
  s.author             = { "xuhui" => "good122000@qq.com" }
  s.ios.deployment_target = "8.0"
  s.source       = { :git => "https://github.com/onesmash/DynamOC.git", :tag => "#{s.version}", :submodules => true }
  s.source_files  = "DynamOC", "DynamOC/**/*.{h,m}"
  s.exclude_files = "DynamOC/DynamOC.h"
  s.public_header_files = "DynamOC/LuaContext.h"
  s.resource_bundles = {
    'DynamOC' => ['DynamOC/runtime.lua', 'DynamOC/boot.lua', 'DynamOC/dispatch.lua', 'DynamOC/cocoa.lua']
  }
  s.library   = "luajit"
  s.dependency "LuaJIT", "~> 0.1.1"

  s.pod_target_xcconfig = {
        'LIBRARY_SEARCH_PATHS' => '$(inherited) $(PODS_ROOT)/LuaJIT/lib'
  }

end
