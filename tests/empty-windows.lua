-- Replay Finder's desktop-only AX list and its WindowServer records without a Space.
local function scenario(opts)
  local pending, snapshotCallback, now, result = nil, nil, 0, {opened=0, reopened=0, launches=0}
  local desktop = {id=function() return 0 end, isStandard=function() return false end}
  local locations = {}
  local existing = 77
  if opts.hidden then locations[existing] = 2 end
  if opts.minimized then locations[existing] = 1 end
  local minimized = opts.minimized
  local screen = {}
  local function window(id)
    return {id=function() return id end, isStandard=function() return not minimized end,
      screen=function() return screen end, isMinimized=function() return minimized end,
      unminimize=function() minimized=false end, raise=function() end,
      focus=function()
        assert(locations[id]==1 and not minimized)
        result.focusAttempts=(result.focusAttempts or 0)+1
        if not opts.dropFirstFocus or result.focusAttempts>1 then result.focus=id end
      end}
  end
  local bid = opts.generic and "test.app" or "com.apple.finder"
  local app = {
    pid=function() return 101 end, isRunning=function() return true end,
    isFrontmost=function() return result.focus~=nil end,
    focusedWindow=function() return result.focus and window(result.focus) or desktop end, mainWindow=function() end,
    allWindows=function()
      local list={desktop}
      for id, space in pairs(locations) do if space==1 then table.insert(list,window(id)) end end
      return list
    end,
    findMenuItem=function(_,path)
      assert(path[1]=="File" and path[2]==(opts.generic and "New Window" or "New Finder Window"))
      return {enabled=not opts.noMenu}
    end,
    selectMenuItem=function()
      result.opened=result.opened+1
      if not opts.ignoredMenu then locations[88]=1 end
      return true
    end,
  }
  local raw={270,68873,68872,68871,68867}
  if opts.hidden or opts.minimized then raw[#raw+1]=existing end
  local hints={pid=101,ids=raw}
  local hs={
    configdir="/pkg", timer={secondsSinceEpoch=function() return now end},
    alert={show=function(msg) result.alert=msg end}, screen={find=function() return screen end},
    application={
      applicationsForBundleID=function(b) assert(b==bid);return {app} end,
      launchOrFocusByBundleID=function(b)
        assert(b==bid);result.launches=result.launches+1
        if opts.restored then locations[existing]=1 end
        return true
      end,
    },
    json={decode=function(v) return v end},
    spaces={
      spaceType=function(space) return opts.fullscreen and space==1 and "fullscreen" or "user" end,
      windowSpaces=function(id) return locations[id] and {locations[id]} or {} end,
      activeSpaceOnScreen=function() return 1 end, spaceDisplay=function() return "screen" end,
      moveWindowToSpace=function(id,space) assert(id==existing);locations[id]=space;return true end,
    },
    task={new=function(path,callback,args)
      if path:match("/AppSearch$") then
        return {start=function(self) snapshotCallback=callback;return self end}
      end
      assert(path=="/usr/bin/open" and args[1]=="-b" and args[2]==bid)
      return {start=function(self)
        result.reopened=result.reopened+1
        if next(locations)==nil then locations[88]=1 end
        return self
      end}
    end},
  }
  local mod=assert(loadfile("window-actions.lua","t",setmetatable({hs=hs},{__index=_G})))()
  mod.run({text="App",bundleID=bid},not opts.cold and app or nil,not opts.missing and hints or nil,opts.mode or "bring",1,{
    stop=function() pending=nil end, after=function(dt,fn) pending=function() now=now+dt;fn() end end,
  })
  for _=1,60 do
    if snapshotCallback then
      local callback=snapshotCallback;snapshotCallback=nil
      callback(opts.failedSnapshot and 1 or 0,hints)
    elseif pending then
      local f=pending;pending=nil;f()
    else break end
  end
  assert(not pending and not snapshotCallback)
  return result
end

for _,opts in ipairs({{}, {missing=true}, {generic=true}, {noMenu=true},
                       {missing=true,failedSnapshot=true}}) do
  local r=scenario(opts)
  assert(r.focus==88 and r.opened+r.reopened==1 and not r.alert, r.alert or "empty app never opened a window")
end
for _,opts in ipairs({{hidden=true,missing=true},{minimized=true,missing=true}}) do
  local r=scenario(opts)
  assert(r.focus==77 and r.opened+r.reopened==0 and not r.alert,"reuse the real window")
end
local r=scenario({dropFirstFocus=true})
assert(r.focus==88 and r.focusAttempts==2 and r.opened+r.reopened==1,"retry focus on the same window")
r=scenario({ignoredMenu=true})
assert(r.focus==88 and r.opened==1 and r.reopened==1 and not r.alert,"recover when the app ignores New Window")
r=scenario({mode="new",hidden=true,missing=true})
assert(r.focus==88 and r.opened==1 and r.reopened==0,"recover missing window list for new-window mode")
for _,mode in ipairs({"bring","new"}) do
  r=scenario({cold=true,fullscreen=true,mode=mode})
  assert(r.launches==1 and not r.alert,"a closed app should launch from any Space")
end
r=scenario({cold=true})
assert(r.launches==1 and r.reopened==1 and r.focus==88 and not r.alert,"recover a windowless launch")
r=scenario({cold=true,restored=true})
assert(r.launches==1 and r.reopened+r.opened==0 and r.focus==77,"reuse the window restored at launch")
print("Windowless, missed snapshot, minimized, hidden and closed app cases passed")
