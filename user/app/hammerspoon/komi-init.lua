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
    T = "kitty",              -- Fixed: was "Terminal"
    C = "Cursor",
    D = "Telegram",
    W = "WhatsApp",
    A = "Arc",
    O = "Obsidian",
    L = "Linear",
    G = "System Settings",    -- Fixed: was "Settings"
    P = "Passwords",          -- User preference: macOS Passwords app
    Q = "Calculator",
    N = "Notes",
    X = "Calendar"
}

-- ============================================================================
-- ADVANCED LAUNCH OR FOCUS
-- ============================================================================

-- Function to launch or focus an app
-- Un-minimizes windows if they're minimized, or creates new window if needed
local function launchOrFocus(appName)
    local app = hs.application.find(appName)
    if app then
        -- First, unhide the app if it's hidden (Cmd+H)
        if app:isHidden() then
            app:unhide()
        end

        -- Try to detect and un-minimize windows using permissive filter
        local wf = hs.window.filter.new(false)
        wf:setAppFilter(appName, {})
        local windows = wf:getWindows()

        -- Un-minimize any minimized windows
        local hasVisibleWindow = false
        for _, win in ipairs(windows) do
            if win:isMinimized() then
                win:unminimize()
                hasVisibleWindow = true
            elseif not win:isMinimized() then
                hasVisibleWindow = true
            end
        end

        -- Activate the app (brings to front)
        app:activate()

        -- If no visible windows exist after activation, try to create one
        if not hasVisibleWindow then
            -- Wait a moment for app to activate, then try creating a new window
            hs.timer.doAfter(0.1, function()
                -- Try common menu items for creating new windows
                if app:selectMenuItem({"File", "New Window"}) then
                    return
                elseif app:selectMenuItem({"Window", "Show"}) then
                    return
                elseif app:selectMenuItem({"Window", "Main Window"}) then
                    return
                end
                -- If no menu item worked, simulate Cmd+N (new window)
                hs.eventtap.keyStroke({"cmd"}, "n", 0, app)
            end)
        end
    else
        -- App not running, launch it
        hs.application.launchOrFocus(appName)
    end
end

-- ============================================================================
-- APP LAUNCHERS (Hyperkey + Key)
-- ============================================================================

-- Bind all app shortcuts
for key, appName in pairs(apps) do
    hs.hotkey.bind(hyper, key, function()
        launchOrFocus(appName)
    end)
end

-- ============================================================================
-- WINDOW SWITCHING CONFIGURATION
-- ============================================================================

local windowSwitchApps = {
    A = "Arc",
    C = "Cursor",
    T = "kitty",      -- Fixed: was "Terminal"
    O = "Obsidian"
}

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

-- ============================================================================
-- WINDOW CYCLING (Hyperkey + Number)
-- ============================================================================

-- Hyper + 1/2/3/4 to switch Arc/Cursor/kitty/Obsidian windows
hs.hotkey.bind(hyper, "1", function() switchWindows("Arc") end)
hs.hotkey.bind(hyper, "2", function() switchWindows("Cursor") end)
hs.hotkey.bind(hyper, "3", function() switchWindows("kitty") end)  -- Fixed: was "Terminal"
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
