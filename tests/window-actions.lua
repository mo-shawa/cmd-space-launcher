-- Run from the repo root with lua tests/window-actions.lua.
-- An old window on desktop 2 is hidden from AX until it is moved to desktop 1.
local function scenario(mode, opts)
  opts = opts or {}
  local loc = {[42] = 2}
  local focus, requests, moves, msg, pending, now = nil, 0, 0, nil, nil, 0
  local screen = {}
  local function window(id)
    return {id=function() return id end, isStandard=function() return true end,
      screen=function() return screen end, isMinimized=function() return false end,
      focus=function() assert(loc[id]==1);focus=id end, raise=function() end}
  end
  local app = {pid=function() return 100 end, isRunning=function() return true end,
    focusedWindow=function() end, mainWindow=function() end,
    allWindows=function()
      local wins={}; for id,space in pairs(loc) do if space==1 then table.insert(wins,window(id)) end end; return wins
    end,
    findMenuItem=function(_,path) assert(path[1]=="File" and path[2]=="New Window"); return {enabled=not opts.unsupported} end,
    selectMenuItem=function() requests=requests+1; if not opts.tab then loc[43]=1 end;return true end}
  local hs = {configdir="/pkg", alert={show=function(m) msg=m end}, screen={find=function() return screen end},
    timer={secondsSinceEpoch=function() return now end},
    spaces={spaceType=function() return opts.fullscreen and "fullscreen" or "user" end,
      spaceDisplay=function() return "display" end, activeSpaceOnScreen=function() return 1 end,
      windowSpaces=function(id) return loc[id] and {loc[id]} or {} end,
      moveWindowToSpace=function(id,space) assert(id==42 and space==1);return true end}, -- reported success, no move
    task={new=function(path,_,args)
      if path:match("/AppSearch$") then return nil end
      assert(path=="/pkg/CmdSpaceLauncher/SpaceMover" and args[1]=="100" and args[2]=="42" and args[3]=="1")
      return {start=function(self) moves=moves+1;if not opts.refuse then loc[42]=1 end;return self end}
    end}}
  local m=assert(loadfile("window-actions.lua","t",setmetatable({hs=hs},{__index=_G})))()
  m.run({bundleID="test",text="Test"},app,{pid=100,ids={42}},mode,1,{
    stop=function() pending=nil end,after=function(dt,fn) now=now+dt;pending=fn end})
  for _=1,50 do if not pending then break end; local f=pending;pending=nil;f() end
  assert(not pending)
  return {loc=loc,focus=focus,requests=requests,moves=moves,msg=msg}
end
local t=scenario("new"); assert(t.focus==43 and t.loc[42]==2 and t.requests==1 and t.moves==0)
t=scenario("bring"); assert(t.focus==42 and t.loc[42]==1 and t.requests==0 and t.moves==1)
t=scenario("bring",{refuse=true}); assert(t.focus==nil and t.loc[42]==2 and t.msg)
t=scenario("new",{tab=true}); assert(t.focus==nil and t.moves==0 and t.msg)
t=scenario("new",{unsupported=true}); assert(t.requests==0 and t.moves==0 and t.msg)
t=scenario("bring",{fullscreen=true}); assert(t.requests==0 and t.moves==0 and t.msg)
print("Per-app window actions passed")
