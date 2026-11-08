-- These actions operate on one window, without activating its old Space first.
local M = {}

local function contains(list, value)
  for _, item in ipairs(list or {}) do if item == value then return true end end
  return false
end

local function standardWindows(app)
  local windows, seen = {}, {}
  local function add(w)
    local id = w and w:id()
    if id and id > 0 and not seen[id] and w:isStandard() then
      seen[id] = true
      table.insert(windows, w)
    end
  end
  add(app:focusedWindow())
  add(app:mainWindow())
  for _, w in ipairs(app:allWindows()) do add(w) end
  return windows
end

-- The panel's WindowServer snapshot includes other Spaces; AX alone may omit them.
local function originalIDs(app, hints)
  local seen = {}
  for _, id in ipairs(hints and hints.ids or {}) do seen[id] = true end
  for _, w in ipairs(standardWindows(app)) do seen[w:id()] = true end
  return seen
end

function M.run(choice, app, hints, mode, origin, op)
  local function finish(message)
    op.stop()
    if message then hs.alert.show(choice.text .. ": " .. message) end
  end
  if not origin or hs.spaces.spaceType(origin) ~= "user" then
    finish("this action needs a regular desktop. Use ⌥Return to switch instead.")
    return
  end
  if not app then
    -- Let a closed app handle its own initial window/session restoration, once.
    local ok = hs.application.launchOrFocusByBundleID(choice.bundleID)
    finish(not ok and "could not launch the app." or nil)
    return
  end
  local original = originalIDs(app, hints)
  local id, window
  if mode == "bring" then
    window = standardWindows(app)[1]
    id = window and window:id()
    if not id then
      for _, hint in ipairs(hints and hints.ids or {}) do
        if #(hs.spaces.windowSpaces(hint) or {}) > 0 then id = hint; break end
      end
    end
  end
  if not id then
    if not hints then finish("could not identify its existing windows. Try ⌥Return."); return end
    if mode == "bring" and next(original) then
      finish("could not identify a movable window. Try ⌥Return."); return
    elseif mode == "bring" then
      hs.task.new("/usr/bin/open", nil, {"-b", choice.bundleID}):start()
    else
      -- Don't send Cmd-N: in many apps it creates a message, project or document.
      local title = choice.bundleID == "com.apple.finder" and "New Finder Window" or "New Window"
      local path = {"File", title}
      local item = app:findMenuItem(path)
      if not item or not item.enabled or not app:selectMenuItem(path) then
        finish("no enabled File → " .. title .. " command. Use ⌥Return to switch.")
        return
      end
    end
  end

  local display = hs.spaces.spaceDisplay(origin)
  local screen = display and hs.screen.find(display)
  local deadline = hs.timer.secondsSinceEpoch() + 3
  local movedAt, bridgeTask, positioned, returned
  local lookup, candidate, nextLookup = nil, nil, deadline - 2.7
  local function place()
    if not app:isRunning() then finish(); return end
    local reason
    local wins = standardWindows(app)
    window = nil
    for _, w in ipairs(wins) do
      if (id and w:id() == id) or (not id and not original[w:id()]) then
        id, window = w:id(), w
        break
      end
    end
    -- The new window can itself open on a hidden desktop. Only accept a
    -- single new, app-owned WindowServer ID not present before the request.
    if not id and candidate and #(hs.spaces.windowSpaces(candidate) or {}) > 0 then id = candidate end
    if not id and not lookup and hs.timer.secondsSinceEpoch() >= nextLookup then
      nextLookup = hs.timer.secondsSinceEpoch() + 0.5
      lookup = hs.task.new(hs.configdir .. "/CmdSpaceLauncher/AppSearch", function(status, out)
        lookup = nil
        local result = status == 0 and hs.json.decode(out)
        if result and result.pid == app:pid() then
          local found = nil
          for _, wid in ipairs(result.ids) do
            if not original[wid] and #(hs.spaces.windowSpaces(wid) or {}) > 0 then
              if found then found = nil; break end
              found = wid
            end
          end
          candidate = found
        end
      end, {"--windows", tostring(app:pid())})
      if lookup then lookup:start() end
    end
    if id then
      if window and window:isMinimized() then window:unminimize() end
      local spaces = hs.spaces.windowSpaces(id) or {}
      if window and screen and window:screen() ~= screen and not positioned
          and #spaces > 0 and hs.spaces.spaceType(spaces[1]) == "user" then
        window:moveToScreen(screen, false, true, 0)
        positioned, movedAt = true, nil
      elseif contains(spaces, origin) then
        if display and hs.spaces.activeSpaceOnScreen(display) ~= origin then
          if not returned then
            local ok = hs.spaces.gotoSpace(origin)
            if not ok then finish("could not return to the original desktop."); return end
            returned = true
          end
        elseif window and (not screen or window:screen() == screen) then
          window:focus()
          window:raise()
          finish()
          return
        end
      elseif #spaces > 0 and not movedAt then
        -- Never force a fullscreen/tiled window out of its Space.
        local ok = hs.spaces.moveWindowToSpace(id, origin)
        if not ok then finish("macOS could not move this window. Try ⌥Return."); return end
        movedAt = hs.timer.secondsSinceEpoch()
      elseif movedAt and not bridgeTask and hs.timer.secondsSinceEpoch() - movedAt > 0.2
          and #spaces > 0 and hs.spaces.spaceType(spaces[1]) == "user" then
        bridgeTask = hs.task.new(hs.configdir .. "/CmdSpaceLauncher/SpaceMover", nil,
          {tostring(app:pid()), tostring(id), tostring(origin)})
        if not bridgeTask or not bridgeTask:start() then finish("could not start the window mover."); return end
      end
      reason = "could not place its window on this desktop."
    else
      reason = "no new window appeared. The app may have opened a tab instead."
    end
    if hs.timer.secondsSinceEpoch() >= deadline then finish(reason)
    else op.after(0.10, place) end
  end
  place()
end

return M
