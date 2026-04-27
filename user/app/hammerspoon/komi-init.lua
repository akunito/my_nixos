-- Komi's Hammerspoon Configuration
-- Migrated from ko-mi/macos-setup with enhancements
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

-- ============================================================================
-- HYPERKEY SETUP
-- ============================================================================

-- Define the hyperkey (Cmd+Ctrl+Alt+Shift)
local hyper = {"cmd", "ctrl", "alt", "shift"}

-- ============================================================================
-- APP LAUNCH CONFIGURATION
-- ============================================================================

local apps = {
    S = "Spotify",
    C = "Cursor",
    T = "Telegram",
    W = "WhatsApp",
    A = "Arc",
    O = "Obsidian",
    L = "Linear",
    Y = "System Settings",
    E = "Passwords",
    Q = "Claude",             -- One-handed access near CapsLock
    N = "Notes",
    X = "Calendar",
    F = "Finder",
    Z = "Calculator",
    V = "kitty",
    B = "Slack",
    G = "Granola",
    U = "NordVPN",
    D = "Discord"
}

-- ============================================================================
-- ADVANCED LAUNCH OR FOCUS
-- ============================================================================

-- Apps that should NOT have Cmd+N triggered (to avoid unwanted behavior)
local appsExcludedFromCmdN = {
    ["WhatsApp"] = true,  -- Cmd+N opens new chat dropdown
}

-- Function to launch or focus an app (simplified and more reliable)
local function launchOrFocus(appName)
    local app = hs.application.find(appName)

    -- Case 1: App not running at all - launch it
    if not app then
        hs.application.launchOrFocus(appName)
        hs.alert.show("Launching " .. appName, 0.5)
        return
    end

    -- Case 2: App is running - unhide if hidden
    if app:isHidden() then
        app:unhide()
    end

    -- Get all windows for this app
    local allWindows = app:allWindows()

    -- If no windows at all, activate app and try to create a window
    if #allWindows == 0 then
        app:activate()
        hs.alert.show("Opening " .. appName .. " window", 0.5)

        -- Wait for app to fully activate, then try multiple methods to create a window
        hs.timer.doAfter(0.3, function()
            -- Try menu items first (most reliable)
            if app:selectMenuItem({"File", "New Window"}) then
                return
            end
            if app:selectMenuItem({"Window", "Show"}) then
                return
            end
            if app:selectMenuItem({"Window", "Main Window"}) then
                return
            end

            -- If menu items didn't work and app allows Cmd+N, try that
            if not appsExcludedFromCmdN[appName] then
                hs.eventtap.keyStroke({"cmd"}, "n", 0, app)
            else
                -- For excluded apps (like WhatsApp), try clicking on Dock icon
                hs.execute("open -a '" .. appName .. "'")
            end
        end)
        return
    end

    -- Separate windows into minimized and visible
    local minimizedWindows = {}
    local visibleWindows = {}

    for _, win in ipairs(allWindows) do
        if win:isMinimized() then
            table.insert(minimizedWindows, win)
        else
            table.insert(visibleWindows, win)
        end
    end

    -- Case 3: Has minimized windows - restore and focus the first one
    if #minimizedWindows > 0 then
        local win = minimizedWindows[1]
        win:unminimize()
        -- Wait for unminimize animation, then activate and focus
        hs.timer.doAfter(0.15, function()
            app:activate()
            win:focus()
            win:raise()
        end)
        hs.alert.show("Restoring " .. appName, 0.5)
        return
    end

    -- Case 4: Only visible windows - just activate and focus
    if #visibleWindows > 0 then
        app:activate()
        visibleWindows[1]:focus()
        visibleWindows[1]:raise()
        return
    end
end

-- ============================================================================
-- WINDOW SWITCHING CONFIGURATION
-- ============================================================================

-- Function to switch between windows of the same app
-- Uses hs.window.filter for better compatibility with Electron apps
local function switchWindows(appName)
    local app = hs.application.find(appName)
    if not app then
        hs.alert.show(appName .. " is not running")
        return
    end

    -- Get all windows without focus-based sorting (use stable order by window ID)
    local wf = hs.window.filter.new(false)
    wf:setAppFilter(appName, {})
    local windows = wf:getWindows()

    if #windows == 0 then
        hs.alert.show("No windows found for " .. appName)
        return
    end

    -- Filter out minimized windows and sort by window ID for stable order
    local visibleWindows = {}
    for _, win in ipairs(windows) do
        if not win:isMinimized() then
            table.insert(visibleWindows, win)
        end
    end

    -- Sort by window ID to maintain consistent order
    table.sort(visibleWindows, function(a, b) return a:id() < b:id() end)

    if #visibleWindows == 0 then
        hs.alert.show("No visible windows for " .. appName)
        return
    end

    if #visibleWindows == 1 then
        visibleWindows[1]:focus()
        return
    end

    -- Get the currently focused window
    local focusedWindow = hs.window.focusedWindow()
    local currentIndex = nil

    -- Find current window index in our stable-sorted list
    for i, win in ipairs(visibleWindows) do
        if focusedWindow and win:id() == focusedWindow:id() then
            currentIndex = i
            break
        end
    end

    -- If current window not found (e.g., different app focused), start at beginning
    if not currentIndex then
        currentIndex = 0
    end

    -- Focus next window (cycle back to 1 if at end)
    local nextIndex = (currentIndex % #visibleWindows) + 1
    visibleWindows[nextIndex]:focus()

    -- Show brief notification with window info
    local nextWin = visibleWindows[nextIndex]
    hs.alert.show(string.format("%d/%d: %s", nextIndex, #visibleWindows,
        nextWin:screen():name():sub(1, 15)), 0.5)
end

-- Function to launch app if not running, focus if minimized, or cycle windows
local function launchOrCycle(appName)
    local app = hs.application.find(appName)

    -- App not running - launch it
    if not app then
        launchOrFocus(appName)
        return
    end

    -- App is running - check window states
    local allWindows = app:allWindows()

    -- No windows - activate and try to create one
    if #allWindows == 0 then
        launchOrFocus(appName)
        return
    end

    -- Check for minimized windows
    local hasMinimized = false
    local hasVisible = false

    for _, win in ipairs(allWindows) do
        if win:isMinimized() then
            hasMinimized = true
        else
            hasVisible = true
        end
    end

    -- If there are minimized windows, restore them
    if hasMinimized then
        launchOrFocus(appName)
        return
    end

    -- All windows are visible - check if we should cycle or just focus
    if not app:isFrontmost() then
        -- App not in front - just bring it forward
        launchOrFocus(appName)
    else
        -- App is already focused - cycle to next window if multiple windows
        if #allWindows > 1 then
            switchWindows(appName)
        end
    end
end

-- ============================================================================
-- APP LAUNCHERS (Hyperkey + Key)
-- ============================================================================

-- Bind all app shortcuts to launch or cycle behavior
for key, appName in pairs(apps) do
    hs.hotkey.bind(hyper, key, function()
        launchOrCycle(appName)
    end)
end

-- ============================================================================
-- WINDOW CYCLING (Hyperkey + Number)
-- ============================================================================

-- Hyper + 1/2/3/4 to switch Arc/Cursor/kitty/Obsidian windows
hs.hotkey.bind(hyper, "1", function() switchWindows("Arc") end)
hs.hotkey.bind(hyper, "2", function() switchWindows("Cursor") end)
hs.hotkey.bind(hyper, "3", function() switchWindows("kitty") end)  -- kitty is now on V, Terminal is on T
hs.hotkey.bind(hyper, "4", function() switchWindows("Obsidian") end)

-- ============================================================================
-- WINDOW MANAGEMENT - MONITORS
-- ============================================================================

-- Hyper + Left Arrow: Move window to previous monitor
hs.hotkey.bind(hyper, "Left", function()
    local win = hs.window.focusedWindow()
    if win then
        win:moveToScreen(win:screen():previous())
        hs.alert.show("Moved to " .. win:screen():name())
    end
end)

-- Hyper + Right Arrow: Move window to next monitor
hs.hotkey.bind(hyper, "Right", function()
    local win = hs.window.focusedWindow()
    if win then
        win:moveToScreen(win:screen():next())
        hs.alert.show("Moved to " .. win:screen():name())
    end
end)

-- ============================================================================
-- WINDOW MANAGEMENT - SIZE
-- ============================================================================

-- Hyper + M: Maximize window on current screen
hs.hotkey.bind(hyper, "M", function()
    local win = hs.window.focusedWindow()
    if win then
        win:maximize()
    end
end)

-- Hyper + H: Minimize window (like clicking yellow button)
hs.hotkey.bind(hyper, "H", function()
    local win = hs.window.focusedWindow()
    if win then
        win:minimize()
    end
end)

-- ============================================================================
-- WINDOW TILING (Hyperkey + J/;/K/I)
-- ============================================================================

-- Left half of screen
hs.hotkey.bind(hyper, "j", function()
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
hs.hotkey.bind(hyper, ";", function()
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
hs.hotkey.bind(hyper, "k", function()
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
hs.hotkey.bind(hyper, "i", function()
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

-- ============================================================================
-- SYSTEM
-- ============================================================================

-- Reload config
hs.hotkey.bind(hyper, "R", function()
    hs.reload()
end)

-- Show notification on successful load
hs.alert.show("Hammerspoon config loaded!", 1.5)
