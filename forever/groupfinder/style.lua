--------------------------------------------------------------------------------
-- forever/groupfinder/style.lua
-- The group finder replica's module: its switch's default, and the sizes and
-- anchors of Blizzard's finder, transcribed from its XML. The data layer is
-- data.lua, Blizzard's frames are host.lua, the window is window.lua and its
-- tabs are listing.lua and the files after it.
--
-- First of the feature's files, and on both clients: retail loads the TOC for
-- the settings panel and excludes the window. Nothing here reads a frame.
--------------------------------------------------------------------------------

local addonName, addon = ...

local DB = addon.DB

addon.ForeverGroupFinder = addon.ForeverGroupFinder or {}
local LFG = addon.ForeverGroupFinder

-- The owner string every event registration carries, and the window's name
LFG.OWNER = "camelotGroupFinder"
LFG.FRAME_NAME = "CamelotGroupFinderFrame"

--------------------------------------------------------------------------------
-- The switch
--------------------------------------------------------------------------------

-- Off until the takeover: the window opens from its slash command and
-- Blizzard's frame keeps the key, the micro button and the queue eye. The
-- Features row comes with the takeover, since a row that takes nothing over
-- would be a switch with no effect.
DB.RegisterDefaults({
    ["groupFinder.enabled"] = false,
})

-- Held for the session, as every feature switch is
function LFG.IsEnabled()
    return DB.SessionGet("groupFinder.enabled") == true
end

--------------------------------------------------------------------------------
-- Layout: Blizzard's own numbers
--------------------------------------------------------------------------------

-- Each table is { point, x, y } or { point, relativePoint, x, y } beside a
-- size, read off the parent frame's, the Listing tab's and the role
-- templates' XML.
LFG.LAYOUT = {
    window = { width = 458, height = 535, default = { "TOPLEFT", 16, -116 } },
    portrait = { size = 64, x = 25, y = -22,
        -- The addon's mark on the eye's lower right, which Blizzard's has not
        mark = { size = 24, x = -15, y = 15, level = 600 } },
    -- icon and crop are for a client whose tab template does not size its
    -- own icon; Forever's fills the tab's interior itself
    sideTabs = { y = -60, gap = -2, icon = 30, crop = 0.03125 },
    titleDrag = { left = 60, right = -30, height = 22 },

    listing = {
        roles = { topLeft = { 2, -25 }, bottomRight = { -2, -127 } },
        divider = { width = 11, height = 454 },
        back = { width = 111, height = 28, x = 21, y = 16 },
        post = { width = 109, height = 28, x = -21, y = 16 },
        buttonLevel = 4,
        soloRoles = { width = 230, height = 48, x = 70, y = -41, gap = 40 },
        groupRoles = { width = 192, height = 48, x = 105, y = -41 },
        groupRoleIcon = { x = 20, y = 0, backgroundAlpha = 0.6 },
        rolePoll = { width = 120, height = 22, x = 6, y = -4 },
        roleDropdown = { width = 120, y = -8 },
        newPlayer = { size = 84, x = -3, y = -30, overlay = 20, overlayX = -8, overlayY = -7,
            check = 24, checkX = 6, checkY = 5 },
        roleCheck = { size = 24, x = -5, y = -5 },
        categoryView = { topLeft = { 8, -124 }, bottomRight = { -8, 40 }, first = -8, gap = -4 },
        activityView = { topLeft = { 7, -125 }, bottomRight = { -7, 40 } },
        barTop = -42,
        barMiddle = 116,
        playstyle = { width = 210, height = 25, x = 28, y = -10 },
        levelCheck = { x = -42, y = -5, textWidth = 120, textHeight = 30, size = 26, gapX = 2, gapY = -1 },
        scrollBox = { top = -45, bottomBase = 88, barInset = -28, rowHeight = 22, padding = 4,
            barX = 13, barTop = -4, barBottom = 2 },
        voiceRow = 36,
        comment = { width = 394, height = 47, bottom = 19, requiredHeight = 110, requiredY = 20 },
        voice = { width = 220, x = -20, y = 12, labelGap = -8 },
        locked = { width = 324, height = 282, x = 22, y = -128, textWidth = 304, errorX = 16, errorY = -20,
            activityY = -8, lineX = 12, lineY = -6, lineGap = -2, maxLines = 13 },
    },

    browse = {
        -- The rectangle Blizzard's hidden BackgroundArt gives the rest
        art = { topLeft = { 4, -80 }, bottomRight = { -4, 3 } },
        stone = { x = 2, y = -21, bottom = -7 },
        insetBg = 3,
        insetBorderTop = 2,
        barTop = -20,
        barMiddle = 61,
        noResults = { width = 240, y = -40 },
        category = { width = 118, x = 70, y = -43 },
        activity = { width = 167, gap = 15 },
        refresh = { size = 32, gap = 9, icon = 16, iconX = -1, pressedX = -2, pressedY = -1 },
        options = { x = -12, y = -32 },
        scrollBox = { left = 7, top = -112, right = -6, bottom = 40, barWidth = 16,
            barX = 2, barTop = -4, barBottom = 2 },
        message = { width = 111, height = 28, x = 21, y = 16 },
        invite = { width = 109, height = 28, x = -21, y = 16 },
        tooltip = { width = 200, x = 8, y = 38, pad = 11, leaderIcon = 18 },
    },
}

-- The portrait eye's color: the Forever bronze where Blizzard's is green.
-- The sum addon.Recolor's two layers come to, for art drawn once.
LFG.EYE_TINT = { 1.0, 0.68, 0.40 }

-- A category button's icon by category id (LFGVanilla_Constants.lua)
LFG.CATEGORY_ICONS = {
    [2] = "groupfinder-button-dungeons",
    [114] = "groupfinder-button-raids-warlords",
    [116] = "groupfinder-button-questing",
    [118] = "groupfinder-button-battlegrounds",
    [120] = "groupfinder-button-custom-pve",
}
LFG.CATEGORY_ICON_DEFAULT = "groupfinder-button-questing"

-- The most activities one listing may carry, where the client does not say
LFG.MAX_ACTIVITIES_FALLBACK = 16
