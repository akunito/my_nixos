-- Komi's Hammerspoon Configuration
-- Based on ko-mi/macos-setup
-- Hyperkey = Cmd + Ctrl + Alt + Shift

-- ============================================================================
-- CONFIG RELOADING
-- ============================================================================

function reloadConfig(files)
  local doReload = false
  for _, file in pairs(files) do
    if file:sub(-4) == ".lua" then
      doReload = true
    end
  end
  if doReload then
    hs.reload()
  end
end

hs.pathwatcher.new(os.getenv("HOME") .. "/.hammerspoon/", reloadConfig):start()
hs.alert.show("Hammerspoon Config Loaded")

-- ============================================================================
-- HYPERKEY SETUP
-- ============================================================================

-- Create a modal hotkey for the hyperkey
hyper = hs.hotkey.modal.new({}, nil)

function hyper:entered() end
function hyper:exited() end

-- Bind the hyperkey to Cmd+Ctrl+Alt+Shift held together
-- We use a "trigger" key approach - hold the modifiers and press a key
local hyperMods = {"cmd", "ctrl", "alt", "shift"}

-- Alternative: Use F18 as hyperkey (requires Karabiner-Elements to map Caps Lock to F18)
-- hs.hotkey.bind({}, "F18", function() hyper:enter() end, function() hyper:exit() end)

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Launch or focus an application
function launchOrFocus(appName)
  local app = hs.application.get(appName)
  if app then
    app:activate()
  else
    hs.application.launchOrFocus(appName)
  end
end

-- Cycle through windows of specified apps
function cycleApp(appNames)
  local frontApp = hs.application.frontmostApplication()
  local frontAppName = frontApp:name()

  -- Find current app index in the list
  local currentIndex = 0
  for i, name in ipairs(appNames) do
    if name == frontAppName then
      currentIndex = i
      break
    end
  end

  -- Cycle to next app or first if not in list/at end
  local nextIndex = currentIndex % #appNames + 1
  launchOrFocus(appNames[nextIndex])
end

-- ============================================================================
-- APP LAUNCHERS (Hyperkey + Key)
-- ============================================================================

-- Using direct hotkey bindings with hyperkey modifiers
-- Format: hs.hotkey.bind(hyperMods, key, function)

-- S - Spotify
hs.hotkey.bind(hyperMods, "s", function() launchOrFocus("Spotify") end)

-- T - Terminal (kitty)
hs.hotkey.bind(hyperMods, "t", function() launchOrFocus("kitty") end)

-- C - Cursor (IDE)
hs.hotkey.bind(hyperMods, "c", function() launchOrFocus("Cursor") end)

-- D - Telegram
hs.hotkey.bind(hyperMods, "d", function() launchOrFocus("Telegram") end)

-- W - WhatsApp
hs.hotkey.bind(hyperMods, "w", function() launchOrFocus("WhatsApp") end)

-- A - Arc Browser
hs.hotkey.bind(hyperMods, "a", function() launchOrFocus("Arc") end)

-- O - Obsidian
hs.hotkey.bind(hyperMods, "o", function() launchOrFocus("Obsidian") end)

-- L - Linear
hs.hotkey.bind(hyperMods, "l", function() launchOrFocus("Linear") end)

-- G - System Settings (was System Preferences)
hs.hotkey.bind(hyperMods, "g", function() launchOrFocus("System Settings") end)

-- P - Passwords (1Password or Keychain Access)
hs.hotkey.bind(hyperMods, "p", function() launchOrFocus("1Password") end)

-- Q - Calculator
hs.hotkey.bind(hyperMods, "q", function() launchOrFocus("Calculator") end)

-- N - Notes
hs.hotkey.bind(hyperMods, "n", function() launchOrFocus("Notes") end)

-- X - Calendar
hs.hotkey.bind(hyperMods, "x", function() launchOrFocus("Calendar") end)

-- ============================================================================
-- WINDOW CYCLING (Hyperkey + Number)
-- ============================================================================

-- 1 - Cycle Arc windows
hs.hotkey.bind(hyperMods, "1", function() cycleApp({"Arc"}) end)

-- 2 - Cycle Cursor windows
hs.hotkey.bind(hyperMods, "2", function() cycleApp({"Cursor"}) end)

-- 3 - Cycle kitty windows
hs.hotkey.bind(hyperMods, "3", function() cycleApp({"kitty"}) end)

-- 4 - Cycle Obsidian windows
hs.hotkey.bind(hyperMods, "4", function() cycleApp({"Obsidian"}) end)

-- ============================================================================
-- WINDOW MANAGEMENT (Hyperkey + Arrow/Letter)
-- ============================================================================

-- Move window to previous monitor (left arrow)
hs.hotkey.bind(hyperMods, "Left", function()
  local win = hs.window.focusedWindow()
  if win then
    local screen = win:screen()
    local prevScreen = screen:previous()
    if prevScreen then
      win:moveToScreen(prevScreen)
    end
  end
end)

-- Move window to next monitor (right arrow)
hs.hotkey.bind(hyperMods, "Right", function()
  local win = hs.window.focusedWindow()
  if win then
    local screen = win:screen()
    local nextScreen = screen:next()
    if nextScreen then
      win:moveToScreen(nextScreen)
    end
  end
end)

-- Maximize window (M)
hs.hotkey.bind(hyperMods, "m", function()
  local win = hs.window.focusedWindow()
  if win then
    win:maximize()
  end
end)

-- Minimize window (H for hide)
hs.hotkey.bind(hyperMods, "h", function()
  local win = hs.window.focusedWindow()
  if win then
    win:minimize()
  end
end)

-- Reload Hammerspoon config (R)
hs.hotkey.bind(hyperMods, "r", function()
  hs.reload()
end)

-- ============================================================================
-- WINDOW POSITIONING (Optional - Hyperkey + IJKL for tiling)
-- ============================================================================

-- Left half of screen
hs.hotkey.bind(hyperMods, "j", function()
  local win = hs.window.focusedWindow()
  if win then
    local f = win:frame()
    local screen = win:screen()
    local max = screen:frame()
    f.x = max.x
    f.y = max.y
    f.w = max.w / 2
    f.h = max.h
    win:setFrame(f)
  end
end)

-- Right half of screen
hs.hotkey.bind(hyperMods, ";", function()
  local win = hs.window.focusedWindow()
  if win then
    local f = win:frame()
    local screen = win:screen()
    local max = screen:frame()
    f.x = max.x + (max.w / 2)
    f.y = max.y
    f.w = max.w / 2
    f.h = max.h
    win:setFrame(f)
  end
end)

-- Top half of screen
hs.hotkey.bind(hyperMods, "k", function()
  local win = hs.window.focusedWindow()
  if win then
    local f = win:frame()
    local screen = win:screen()
    local max = screen:frame()
    f.x = max.x
    f.y = max.y
    f.w = max.w
    f.h = max.h / 2
    win:setFrame(f)
  end
end)

-- Bottom half of screen
hs.hotkey.bind(hyperMods, "i", function()
  local win = hs.window.focusedWindow()
  if win then
    local f = win:frame()
    local screen = win:screen()
    local max = screen:frame()
    f.x = max.x
    f.y = max.y + (max.h / 2)
    f.w = max.w
    f.h = max.h / 2
    win:setFrame(f)
  end
end)
