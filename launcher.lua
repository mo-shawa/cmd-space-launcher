-- Cmd-Space launcher: type an app name, Enter.
-- Running app -> jumps to it (switches Space like Cmd-Tab) and unminimizes it.
-- Closed app  -> launches it.

hs.autoLaunch(true)
hs.dockicon.hide()

local dirs = {
  "/Applications",
  "/Applications/Utilities",
  "/System/Applications",
  "/System/Applications/Utilities",
  os.getenv("HOME") .. "/Applications",
}

local aliases = {
  ["com.openai.codex"] = { "codex" },
}
local cache = {}

local function rebuild()
  local choices, seen = {}, {}
  for _, dir in ipairs(dirs) do
    local ok, iter, data = pcall(hs.fs.dir, dir)
    if ok and iter then
      for file in iter, data do
        if file:match("%.app$") then
          local info = hs.application.infoForBundlePath(dir .. "/" .. file)
          local bid = info and info.CFBundleIdentifier
          if bid and not seen[bid] then
            seen[bid] = true
            table.insert(choices, {
              text = (file:gsub("%.app$", "")),
              bundleID = bid,
              path = dir .. "/" .. file,
              aliases = aliases[bid],
            })
          end
        end
      end
    end
  end
  table.sort(choices, function(a, b) return a.text:lower() < b.text:lower() end)
  cache = choices
end

rebuild()

-- Refresh the list only when apps are installed or removed.
local appWatchers = {}
for _, dir in ipairs(dirs) do
  if hs.fs.attributes(dir) then
    local w = hs.pathwatcher.new(dir, function() hs.timer.doAfter(2, rebuild) end)
    w:start()
    table.insert(appWatchers, w)
  end
end

local focusTimer, inputGuard
local function cancelPendingFocus()
  if focusTimer then focusTimer:stop(); focusTimer = nil end
  if inputGuard then inputGuard:stop(); inputGuard = nil end
end

local function targetWindow(app)
  local preferred = app:focusedWindow() or app:mainWindow()
  if preferred and preferred:id() and preferred:isVisible() then return preferred end
  local minimized
  for _, window in ipairs(app:allWindows()) do
    if window:id() and window:isStandard() then
      if window:isVisible() then return window end
      if window:isMinimized() and not minimized then minimized = window end
    end
  end
  return minimized
end

-- A window can belong to more than one Space. A Space on any visible display counts.
local function windowSpace(id, active)
  if not id or not active then return end
  local spaces = hs.spaces.windowSpaces(id) or {}
  for _, space in ipairs(spaces) do
    for _, visible in pairs(active) do
      if space == visible then return space, true end
    end
  end
  if spaces[1] then return spaces[1], false end
end

local function locateWindow(id, window, hints)
  local active = hs.spaces.activeSpaces()
  local space, visible = windowSpace(id, active)
  if space then return id, space, visible end
  if window and window:id() ~= id then
    id = window:id()
    space, visible = windowSpace(id, active)
    if space then return id, space, visible end
  end
  for _, candidate in ipairs(hints and hints.ids or {}) do
    space, visible = windowSpace(candidate, active)
    if space then return candidate, space, visible end
  end
  return id
end

local function goTo(choice, hints)
  cancelPendingFocus()
  if not choice then return end
  local bid = choice.bundleID
  local app = hints and hs.application.applicationForPID(hints.pid)
  if not app or app:bundleID() ~= bid then
    app = hs.application.applicationsForBundleID(bid)[1]
    hints = nil
  end

  if not app then
    hs.application.launchOrFocusByBundleID(bid)
    return
  end

  local preferred = targetWindow(app)
  local targetID = preferred and preferred:id()
  app:activate()
  -- A click or keypress starts a new action. Let it take precedence over a delayed raise.
  local events = hs.eventtap.event.types
  inputGuard = hs.eventtap.new({events.leftMouseDown, events.rightMouseDown, events.otherMouseDown,
    events.keyDown, events.scrollWheel}, function()
    cancelPendingFocus()
    return false
  end):start()

  local switched, waitUntil
  local function raiseWindow(final)
    if not app:isRunning() then cancelPendingFocus(); return end
    local window = targetWindow(app) or preferred
    local space, visible
    targetID, space, visible = locateWindow(targetID, window, hints)
    if space and not switched then
      local wrongDisplay = final and hs.spaces.focusedSpace() ~= space and not app:isFrontmost()
      if not visible or wrongDisplay then
        switched = true
        local ok, err = hs.spaces.gotoSpace(space)
        if ok then
          waitUntil = hs.timer.secondsSinceEpoch() + 1.5
          focusTimer = hs.timer.doAfter(0.2, function() raiseWindow(false) end)
          return
        end
        hs.spaces.closeMissionControl()
        print("App Search: could not switch to Space " .. space .. ": " .. tostring(err))
      end
    end
    if waitUntil and space and not visible and hs.timer.secondsSinceEpoch() < waitUntil then
      focusTimer = hs.timer.doAfter(0.15, function() raiseWindow(false) end)
      return
    end
    if targetID and (not window or window:id() ~= targetID) then
      for _, candidate in ipairs(app:allWindows()) do
        if candidate:id() == targetID then window = candidate; break end
      end
    end
    if window then
      if window:isMinimized() then window:unminimize() end
      window:focus()
      window:raise()
    elseif final then
      hs.task.new("/usr/bin/open", nil, {"-b", bid}):start()
    end
    if final then
      cancelPendingFocus()
    else
      focusTimer = hs.timer.doAfter(0.5, function() raiseWindow(true) end)
    end
  end
  -- Window order can change a second time as Mission Control finishes switching desktops.
  focusTimer = hs.timer.doAfter(0.45, function() raiseWindow(false) end)
end

local panelTask
local panelPath = hs.configdir .. "/CmdSpaceLauncher/AppSearch"
local historyKey = "CmdSpaceLauncher.history.v1"

local function remember(bundleID, query)
  local history = hs.settings.get(historyKey) or {}
  local recent = {bundleID}
  for _, id in ipairs(history.recent or {}) do
    if id ~= bundleID and #recent < 12 then table.insert(recent, id) end
  end
  history.recent = recent
  if query then
    local learned = {{query = query, bundleID = bundleID}}
    for _, pick in ipairs(history.learned or {}) do
      if pick.query ~= query and #learned < 128 then table.insert(learned, pick) end
    end
    history.learned = learned
  end
  hs.settings.set(historyKey, history)
end

local hotkey = hs.hotkey.bind({ "cmd" }, "space", function()
  cancelPendingFocus()
  if panelTask and panelTask:isRunning() then
    panelTask:terminate()
    return
  end
  local choices = cache
  local task
  task = hs.task.new(panelPath, function(status, output, errors)
    if panelTask == task then panelTask = nil end
    if status ~= 0 then
      if errors and errors ~= "" then print("App Search: " .. errors) end
      return
    end
    if not output or output == "" then return end
    local selection = hs.json.decode(output)
    if not selection then return end
    for _, choice in ipairs(choices) do
      if choice.bundleID == selection.bundleID then
        remember(choice.bundleID, selection.shortQuery)
        goTo(choice, selection.windows)
        return
      end
    end
  end)
  if task then
    local history = hs.settings.get(historyKey) or {}
    task:setInput(hs.json.encode({
      choices = #choices > 0 and choices or nil,
      learned = history.learned,
      recent = history.recent,
      -- Keep an empty catalog a JSON object on a fresh install.
      version = 1,
    }))
    panelTask = task:start()
  end
  if not panelTask then hs.alert.show("Could not open App Search") end
end)

return {hotkey = hotkey, watchers = appWatchers}
