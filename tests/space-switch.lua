-- Run from the repo root with lua tests/space-switch.lua.
-- The source display stays on Space 10. The app's window lives on Space 21.
local function selectApp(startSpace, cancel)
  local space, switches, raises = startSpace, 0, 0
  local pending, stopped, bind, selected, input, switching
  local window = {
    id = function() return 42 end,
    isVisible = function() return true end,
    isMinimized = function() return false end,
    focus = function() assert(space == 21) end,
    raise = function() raises = raises + 1 end,
  }
  local function availableWindow()
    if space == 21 then return window end
  end
  local app = {
    bundleID = function() return "test.app" end,
    -- Model a native activation that succeeds without revealing the window's Space.
    activate = function() return true end,
    isRunning = function() return true end,
    isFrontmost = function() return raises > 0 end,
    focusedWindow = availableWindow, mainWindow = availableWindow,
    allWindows = function() return {availableWindow()} end,
  }
  local hs = {
    configdir = ".", autoLaunch = function() end, dockicon = {hide = function() end},
    fs = {attributes = function() end, dir = function(path)
      return coroutine.wrap(function()
        if path == "/Applications" then coroutine.yield("Example.app") end
      end)
    end},
    application = {
      get = function() return app end,
      infoForBundlePath = function() return {CFBundleIdentifier = "test.app"} end,
      applicationForPID = function(pid) assert(pid == 123); return app end,
    },
    settings = {get = function() end, set = function() end},
    json = {encode = function(v) return v end, decode = function(v) return v end},
    hotkey = {bind = function(_, _, f) bind = f; return {} end},
    task = {new = function(path, f)
      assert(path:match("AppSearch$"), "must not reopen an app that has an existing window")
      selected = f
      return {setInput = function() end, start = function(self) return self end}
    end},
    spaces = {
      activeSpaces = function() return {source = 10, destination = space} end,
      windowSpaces = function(id) return id == 42 and {21} or {} end,
      focusedSpace = function() return raises > 0 and 21 or 10 end,
      gotoSpace = function(id)
        assert(id == 21); switches = switches + 1; switching = true; return true
      end,
    },
    timer = {
      secondsSinceEpoch = function() return 100 end,
      doAfter = function(_, f)
        pending, stopped = f, false
        return {stop = function() stopped = true end}
      end,
    },
    eventtap = {event = {types = {}}, new = function(_, f)
      input = f
      return {start = function(self) return self end, stop = function() end}
    end},
  }
  assert(loadfile("launcher.lua", "t", setmetatable({hs = hs}, {__index = _G})))()
  bind()
  selected(0, {bundleID = "test.app", windows = {pid = 123, ids = {99, 42}}}, "")
  if cancel then input() end
  for _ = 1, 8 do
    if not pending or stopped then break end
    local f, inTransition = pending, switching
    pending = nil
    f()
    if inTransition then space = 21 end
  end
  assert(not pending or stopped, "focus retries must end")
  return switches, raises
end

local switches, raises = selectApp(20, false)
assert(switches == 1 and raises > 0, "reveal a hidden window on the other display")
switches, raises = selectApp(21, false)
assert(switches == 0 and raises > 0, "leave already-visible desktops alone")
switches, raises = selectApp(20, true)
assert(switches == 0 and raises == 0, "respect a new user action")
print("Cross-display selection passed")
