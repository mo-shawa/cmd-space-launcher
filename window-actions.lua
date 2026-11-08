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
    -- Finder can change a minimized folder window's AX subrole to AXDialog.
    if id and id > 0 and not seen[id] and (w:isStandard() or w:isMinimized()) then
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
local function originalIDs(windows, hints)
  local seen = {}
  for _, id in ipairs(hints and hints.ids or {}) do seen[id] = true end
  for _, w in ipairs(windows) do seen[w:id()] = true end
  return seen
end

local function snapshot(pid, callback)
  local task = hs.task.new(hs.configdir .. "/CmdSpaceLauncher/AppSearch", function(status, out)
    local result = status == 0 and hs.json.decode(out)
    callback(result and result.pid == pid and type(result.ids) == "table" and result or nil)
  end, {"--windows", tostring(pid)})
  return task and task:start()
end

local function newWindowCommand(app, bid)
  -- Cmd-N can create a message or document. Use only an actual new-window menu item.
  local title = bid == "com.apple.finder" and "New Finder Window" or "New Window"
  local path = {"File", title}
  local item = app:findMenuItem(path)
  return item and item.enabled and app:selectMenuItem(path), title
end

local function reopen(bid)
  local task = hs.task.new("/usr/bin/open", nil, {"-b", bid})
  return task and task:start()
end

local function runWithWindows(choice, app, hints, mode, origin, op, finish, launched)
  local windows = standardWindows(app)
  local original = originalIDs(windows, hints)
  local id, window
  if mode == "bring" then
    window = windows[1]
    id = window and window:id()
    if not id then
      for _, hint in ipairs(hints and hints.ids or {}) do
        if #(hs.spaces.windowSpaces(hint) or {}) > 0 then id = hint; break end
      end
    end
  end
  local regular = origin and hs.spaces.spaceType(origin) == "user"
  if not regular and (mode == "new" or id) then
    if launched then finish(); return end
    finish("this action needs a regular desktop. Use ⌥Return to switch instead.")
    return
  end
  local mayReopen = mode == "bring" and id ~= nil
  if mode == "new" then
    local ok, title = newWindowCommand(app, choice.bundleID)
    if not ok then finish("no enabled File → " .. title .. " command. Use ⌥Return to switch."); return end
    -- Without a baseline we can issue the request, but cannot safely move an
    -- unidentified window which might have existed before the selection.
    if not hints then finish("requested a new window. The app will choose its desktop."); return end
  elseif not id then
    -- Space-less WindowServer records (e.g. Finder chrome) aren't movable windows.
    -- With an inconclusive snapshot, a Dock-style reopen lets the app reuse a window.
    local requested = not launched and hints and newWindowCommand(app, choice.bundleID)
    mayReopen = requested
    if not requested and not reopen(choice.bundleID) then
      finish("could not ask the app to reopen."); return
    end
    if not regular then finish(); return end
  end

  local display = hs.spaces.spaceDisplay(origin)
  local screen = display and hs.screen.find(display)
  local deadline = hs.timer.secondsSinceEpoch() + 3
  local movedAt, bridgeTask, positioned, returned
  local nextFocus = 0
  local lookup, candidate, nextLookup = nil, nil, deadline - 2.7
  local function place()
    if not app:isRunning() then finish(); return end
    local reason
    local wins = standardWindows(app)
    window = nil
    for _, w in ipairs(wins) do
      if (id and w:id() == id) or (not id and (mode == "bring" or not original[w:id()])) then
        id, window = w:id(), w
        break
      end
    end
    -- The new window can itself open on a hidden desktop. Only accept a
    -- single new, app-owned WindowServer ID not present before the request.
    if not id and candidate and #(hs.spaces.windowSpaces(candidate) or {}) > 0 then id = candidate end
    if not id and not lookup and hs.timer.secondsSinceEpoch() >= nextLookup then
      nextLookup = hs.timer.secondsSinceEpoch() + 0.5
      lookup = snapshot(app:pid(), function(result)
        lookup = nil
        if result then
          local found = nil
          for _, wid in ipairs(result.ids) do
            if not original[wid] and #(hs.spaces.windowSpaces(wid) or {}) > 0 then
              if found then found = nil; break end
              found = wid
            end
          end
          candidate = found
        end
      end)
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
        elseif window and (not screen or window:screen() == screen) and not window:isMinimized() then
          local focused = app:focusedWindow()
          if app:isFrontmost() and focused and focused:id() == id then
            window:raise()
            finish()
            return
          end
          local now = hs.timer.secondsSinceEpoch()
          if now >= nextFocus then
            window:focus()
            window:raise()
            nextFocus = now + 0.25
          end
          reason = "could not focus its window on this desktop."
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
      reason = reason or "could not place its window on this desktop."
    else
      reason = mode == "bring" and "the app did not present a window after reopening."
        or "no new window appeared. The app may have opened a tab instead."
    end
    if hs.timer.secondsSinceEpoch() < deadline then op.after(0.10, place); return end
    local membership = id and hs.spaces.windowSpaces(id) or {}
    if mayReopen and not window and (#membership == 0 or contains(membership, origin)) then
      -- A window can close during selection, or a menu request can produce no
      -- window. Give the app one Dock-style reopen and accept the window it presents.
      if not reopen(choice.bundleID) then finish("could not ask the app to reopen."); return end
      if id then original[id] = true end
      id, candidate, mayReopen = nil, nil, false
      movedAt, bridgeTask, positioned, returned = nil, nil, nil, nil
      deadline = hs.timer.secondsSinceEpoch() + 3
      op.after(0.10, place)
    else finish(reason) end
  end
  place()
end

local function resolveWindows(choice, app, hints, mode, origin, op, finish, launched)
  local function proceed(list)
    if not app:isRunning() then finish(); return end
    runWithWindows(choice, app, list, mode, origin, op, finish, launched)
  end
  if hints or (mode == "bring" and standardWindows(app)[1]) then proceed(hints); return end

  -- A running app may be resolved by bundle ID after the panel missed its PID.
  -- Retry the cross-Space list before deciding whether the app has a window.
  local done, result
  local task = snapshot(app:pid(), function(list) done, result = true, list end)
  local limit = hs.timer.secondsSinceEpoch() + 1
  local function waitForList()
    if done or not task or hs.timer.secondsSinceEpoch() >= limit then proceed(result)
    else op.after(0.05, waitForList) end
  end
  waitForList()
end

function M.run(choice, app, hints, mode, origin, op)
  local function finish(message)
    op.stop()
    if message then hs.alert.show(choice.text .. ": " .. message) end
  end
  if app and app:isRunning() then
    resolveWindows(choice, app, hints, mode, origin, op, finish, false)
    return
  end
  if not hs.application.launchOrFocusByBundleID(choice.bundleID) then
    finish("could not launch the app.")
    return
  end
  if mode ~= "bring" then finish(); return end

  -- A missed process lookup looks like a cold launch. Give the app time to
  -- restore its session before asking it to reopen a still-empty window list.
  local limit = hs.timer.secondsSinceEpoch() + 6
  local restoreUntil
  local function waitForApp()
    local now = hs.timer.secondsSinceEpoch()
    local running = hs.application.applicationsForBundleID(choice.bundleID)[1]
    if running then
      restoreUntil = restoreUntil or now + 2
      if standardWindows(running)[1] or now >= math.min(restoreUntil, limit) then
        resolveWindows(choice, running, nil, mode, origin, op, finish, true)
        return
      end
    end
    if now >= limit then finish("launched, but could not find its window.")
    else op.after(0.15, waitForApp) end
  end
  op.after(0.15, waitForApp)
end

return M
