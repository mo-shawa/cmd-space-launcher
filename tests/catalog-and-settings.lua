local root="/System/Library/CoreServices/Applications"
local dirs={["/Applications"]={"Example.app"}, [root]={"Archive Utility.app","Agent.app","Background.app","About This Mac.app","Duplicate.app"},
  ["/Xcode.app/Contents/Developer/Applications"]={"Simulator.app"}}
local meta={Example={"example"},["Archive Utility"]={"archive"},Agent={"ignored","1"},Background={"ignored.bg",nil,true},
  ["About This Mac"]={"com.apple.AboutThisMacLauncher",true},Duplicate={"example"},Finder={"com.apple.finder"},Simulator={"simulator"}}
local bind, reply, input, prefs
prefs={}
local hs={configdir="/test",autoLaunch=function() end,dockicon={hide=function() end},
  fs={attributes=function() end,dir=function(path)
    assert(not path:match("/CoreServices$"),"must not crawl all CoreServices helpers")
    return coroutine.wrap(function() for _,f in ipairs(dirs[path] or {}) do coroutine.yield(f) end end)
  end},
  application={infoForBundlePath=function(p)
    local i=assert(meta[p:match("([^/]+)%.app$")]);return {CFBundleIdentifier=i[1],LSUIElement=i[2],LSBackgroundOnly=i[3]}
  end,pathForBundleID=function(id) return ({["com.apple.finder"]="/CoreServices/Finder.app",["com.apple.dt.Xcode"]="/Xcode.app"})[id] end},
  spaces={focusedSpace=function() return 1 end},
  settings={get=function(k)return prefs[k]end,set=function(k,v)prefs[k]=v end},
  json={encode=function(v)return v end,decode=function(v)return v end},hotkey={bind=function(_,_,fn)bind=fn end},
  task={new=function(_,fn) reply=fn;return {setInput=function(_,v)input=v end,start=function(self)return self end} end}}
assert(loadfile("launcher.lua","t",setmetatable({hs=hs},{__index=_G})))()
bind()
local seen={};for _,c in ipairs(input.choices) do assert(not seen[c.bundleID]);seen[c.bundleID]=true end
assert(#input.choices==5 and seen["com.apple.finder"] and seen["com.apple.AboutThisMacLauncher"] and seen.simulator and seen.archive)
reply(0,{bundleID="example",saveMode="bring"},"")
bind();assert(input.rules.example=="bring");reply(0,{bundleID="com.apple.finder",saveMode="new"},"")
bind();assert(input.rules["com.apple.finder"]=="new");reply(0,{bundleID="example",saveMode="switch"},"")
bind();assert(input.rules.example==nil and input.rules["com.apple.finder"]=="new");reply(0,"","")
assert(not prefs["CmdSpaceLauncher.history.v1"],"editing settings must not record a launch")
print("Catalog filtering and per-app settings passed")
