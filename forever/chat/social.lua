--------------------------------------------------------------------------------
-- forever/chat/social.lua
-- The social tab: Blizzard's friends button, QuickJoinToastButton, which
-- stands above and left of its chat with the online count and is parked with
-- the rest (display.lua), rebuilt as the first tab on the strip, narrower
-- than a window's tab. The icon is Blizzard's Friends tab glyph from its
-- social window, sized to the count's font: the button's own silhouette is
-- one sprite with its bezel and fill, and the client has no lone figure. The
-- count is the button's own sum (QuickJoinToastMixin:UpdateDisplayedFriendCount),
-- the click its own, Blizzard's Friends frame (QuickJoinToastMixin:OnClick),
-- the tooltip its own. The Quick Join toast the button also carries is not
-- drawn (question 64). Not built where Blizzard hides the button, the
-- in-game friends list game rule. Every Blizzard name is read through _G
-- behind a guard.
--------------------------------------------------------------------------------

local addonName, addon = ...

local CR = addon.ChatReplica
local Style = CR.Style

local Social = {}
CR.Social = Social

-- The Friends tab's glyph in Blizzard's social window, two gold figures on
-- nothing, and its dimmed member for the press
-- (Blizzard_SocialUI/Mainline/SocialUI.lua:178-179). The sprite is 33 square
-- with the figures on 27 of it, so the texture is drawn a quarter over the
-- count's font height for the figures to stand as tall as the digits.
local ICON_UP = "friends-icon-tab-friends"
local ICON_DOWN = "friends-icon-tab-friends-inactive"
local ICON_OVER_FONT = 1.25
local ICON_FALLBACK = 12
local PAD = 7           -- the tab's edge to the icon, and the count to the edge
local GAP = 1           -- the icon to the count
local MIN_WIDTH = 34    -- under the window tabs' 60
local TEXT_Y = -5       -- the tab text's own offset (frames.xml)
local DIGIT_WIDTH = 7   -- a stand-in when the count cannot be measured yet

local tab
local count = 0

local function isSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

local function plainNumber(v)
    return type(v) == "number" and not isSecret(v)
end

local function hasAtlas(name)
    local api = _G.C_Texture
    if not (api and api.GetAtlasInfo) then return false end
    local ok, info = pcall(api.GetAtlasInfo, name)
    return ok and info ~= nil
end

--- The globalstring, or the fallback when the client lacks it.
local function label(global, fallback)
    local s = _G[global]
    if type(s) == "string" and not isSecret(s) and s ~= "" then return s end
    return fallback
end

--- Blizzard's sum: online Battle.net friends, plus online character friends
--- where the legacy list is on (QuickJoinToast.lua:160-164).
local function onlineFriends()
    local n = 0
    local okB, _, bnetOnline = pcall(function() return _G.BNGetNumFriends() end)
    if okB and plainNumber(bnetOnline) then n = n + bnetOnline end
    local api = _G.C_FriendList
    if api and api.GetNumOnlineFriends then
        local okL, legacy = pcall(function()
            return api.IsLegacyFriendSystemEnabled == nil or api.IsLegacyFriendSystemEnabled() == true
        end)
        if okL and legacy then
            local okW, wow = pcall(api.GetNumOnlineFriends)
            if okW and plainNumber(wow) then n = n + wow end
        end
    end
    return n
end

--- Blizzard hides its button where the in-game friends list is off
--- (QuickJoinToastMixin:OnLoad).
local function friendsListOff()
    local rules, enum = _G.C_GameRules, _G.Enum
    local rule = enum and enum.GameRule and enum.GameRule.IngameFriendsListDisabled
    if not (rules and rules.IsGameRuleActive and rule) then return false end
    local ok, off = pcall(rules.IsGameRuleActive, rule)
    return ok and off == true
end

--------------------------------------------------------------------------------
-- Scripts
--------------------------------------------------------------------------------

--- The button's click: Blizzard's Friends frame on its Friends tab.
local function onClick()
    local toggle = _G.ToggleFriendsFrame
    if type(toggle) ~= "function" then return end
    pcall(toggle, _G.FRIEND_TAB_FRIENDS or 1)
end

--- The button's tooltip: Social with its key (QuickJoinToast.lua:375-378).
local function onEnter(self)
    if not GameTooltip then return end
    local title = label("SOCIAL_BUTTON", "Social")
    local ok, text = pcall(function() return _G.MicroButtonTooltipText(title, "TOGGLESOCIAL") end)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(ok and type(text) == "string" and text or title)
    GameTooltip:Show()
end

local function onLeave()
    if GameTooltip then GameTooltip:Hide() end
end

--------------------------------------------------------------------------------
-- The tab
--------------------------------------------------------------------------------

--- The tab's width from its content, the padding each side.
local function size()
    local text = tab.Text
    local width = text:GetStringWidth()
    if not plainNumber(width) or width <= 0 then
        width = #tostring(text:GetText() or "") * DIGIT_WIDTH
    end
    local inner = (tab.Icon and (tab.iconSize + GAP) or 0) + width
    tab:SetWidth(math.max(MIN_WIDTH, math.floor(inner + PAD * 2 + 0.5)))
end

--- The glyph's side from the count's font height.
local function iconSize(text)
    local ok, _, height = pcall(text.GetFont, text)
    if ok and plainNumber(height) and height > 0 then
        return math.floor(height * ICON_OVER_FONT + 0.5)
    end
    return ICON_FALLBACK
end

--- The count re-read and the tab sized.
function Social.Refresh()
    if not tab then return end
    count = onlineFriends()
    if tab.Icon then
        tab:SetText(tostring(count))
    else
        tab:SetText(string.format("%s %d", label("SOCIAL_BUTTON", "Social"), count))
    end
    size()
end

--- The tab, or nil before the build and where Blizzard hides the button;
--- the strip anchors the window tabs after it.
function Social.Tab()
    return tab
end

--- The selected tab's alphas, so the button reads at the window's rest and
--- rises under the mouse; Tabs.UpdateState's call.
function Social.UpdateState(mouseOver)
    if not tab then return end
    local a = CR.Tabs and CR.Tabs.Alphas and CR.Tabs.Alphas()
    if not a then return end
    tab:SetAlpha(mouseOver and a.selectedOver or a.selectedIdle)
end

--- The tab on the strip's left; Tabs.Build's call, before the window tabs.
function Social.Build(strip)
    if tab or friendsListOff() then return end
    tab = CreateFrame("Button", (addon.Brand or "Camelot") .. "ChatSocialTab", strip, "CamelotChatTabTemplate")
    tab:SetHeight(Style.TAB_HEIGHT)
    tab:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", 0, 0)
    tab:RegisterForClicks("LeftButtonUp")
    local text = tab.Text
    text:ClearAllPoints()
    text:SetWidth(0)
    if hasAtlas(ICON_UP) then
        local icon = tab:CreateTexture(nil, "ARTWORK")
        tab.iconSize = iconSize(text)
        icon:SetSize(tab.iconSize, tab.iconSize)
        icon:SetAtlas(ICON_UP)
        icon:SetPoint("LEFT", tab, "LEFT", PAD, TEXT_Y)
        tab.Icon = icon
        text:SetPoint("LEFT", icon, "RIGHT", GAP, 0)
        if hasAtlas(ICON_DOWN) then
            tab:SetScript("OnMouseDown", function() icon:SetAtlas(ICON_DOWN) end)
            tab:SetScript("OnMouseUp", function() icon:SetAtlas(ICON_UP) end)
        end
    else
        text:SetPoint("CENTER", tab, "CENTER", 0, TEXT_Y)
    end
    tab:SetScript("OnClick", onClick)
    tab:SetScript("OnEnter", onEnter)
    tab:SetScript("OnLeave", onLeave)
    if CR.Tabs and CR.Tabs.UpdateColors then CR.Tabs.UpdateColors(tab, false) end
    Social.Refresh()
    tab:Show()
end

--- A line for /camelot chat.
function Social.Describe(push)
    push("  social tab: %s, %d online, width %.0f, icon %s",
        tab and (tab:IsShown() and "shown" or "hidden") or (friendsListOff() and "off by game rule" or "unbuilt"),
        count, tab and tab:GetWidth() or 0, tab and tab.Icon and ("atlas at " .. tab.iconSize) or "text")
end

-- The events Blizzard's friends list refreshes the count on (FriendsFrame.lua:292-308, :817).
for _, event in ipairs({
    "FRIENDLIST_UPDATE", "BN_FRIEND_INFO_CHANGED", "BN_FRIEND_LIST_SIZE_CHANGED",
    "BN_CONNECTED", "BN_DISCONNECTED", "PLAYER_ENTERING_WORLD",
}) do
    addon.Events.On(CR.OWNER .. "Social", event, Social.Refresh)
end
