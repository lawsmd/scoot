--------------------------------------------------------------------------------
-- forever/actionbars/micro.lua
-- The micro menu replica: one Camelot button per Forever micro button, drawn
-- in Blizzard's art and laid out as Blizzard's MicroMenu lays its buttons.
-- Each is a secure click twin (type "click", clickbutton the Blizzard button),
-- so a hardware click runs Blizzard's own OnClick untainted, in combat too,
-- and the panel it opens stays clean: Scoot's game menu opens the store the
-- same way. Blizzard's buttons stay parked with MicroMenuContainer and keep
-- every piece of their own state; the twins read it and draw it:
--
--   * the atlases, by the textureName LoadMicroButtonTextures stores, and the
--     guild color off the normal texture's vertex color;
--   * pushed or normal, off the button state UpdateMicroButtons sets;
--   * enabled, alpha, the notification overlay, the portrait's desaturation
--     and the guild emblem, read at every sync;
--   * the alert flash, from hooks on MicroButtonPulse and MicroButtonPulseStop.
--
-- The syncs run from hooks on Blizzard's global functions and from the
-- callbacks Forever's buttons fire (OnEnable, OnDisable, OnNewNotification,
-- OnDismissedNotification), never from a write to a Blizzard button. The
-- game menu button's stream and latency art runs on the replica's own
-- ticker: Blizzard's runs in an OnUpdate, which a parked button never gets.
--
-- The list, the sizes and the art are Forever's own Blizzard_MicroMenu files,
-- which differ from retail's.
--------------------------------------------------------------------------------

local _, addon = ...

local ActionBars = addon.ActionBars
local MicroBags = ActionBars.MicroBags

local Micro = {}
MicroBags.Micro = Micro

local PREFIX = "UI-HUD-MicroMenu-"

-- Forever's MicroMenuMixin:GenerateButtonInfos, in its order. A button is
-- drawn while Blizzard's is shown, which is how the game rules and the
-- hidden Help button reach the replica.
Micro.ORDER = {
    "CharacterMicroButton", "ProfessionMicroButton", "SpellbookMicroButton", "TalentMicroButton",
    "LegacyMicroButton", "QuestLogMicroButton", "HousingMicroButton", "GuildMicroButton",
    "LFDMicroButton", "CollectionsMicroButton", "EJMicroButton", "HelpMicroButton",
    "StoreMicroButton", "MainMenuMicroButton",
}

-- The template's numbers (MainMenuBarMicroButtons.xml and the menu template).
Micro.WIDTH = 32
Micro.HEIGHT = 40
Micro.PADDING = -5

-- Blizzard's own thresholds, local to their file.
local LOW_LATENCY = 300
local MEDIUM_LATENCY = 600

local buttons = {}      -- in Micro.ORDER, the built twins
local byBlizzard = {}   -- Blizzard button -> twin
Micro.Buttons = buttons

--------------------------------------------------------------------------------
-- Art
--------------------------------------------------------------------------------

local function texture(btn, key, layer, sublevel)
    local t = btn:CreateTexture(nil, layer, nil, sublevel or 0)
    btn[key] = t
    return t
end

local function LoadTextures(btn, name)
    btn.textureName = name
    btn:SetNormalAtlas(PREFIX .. name .. "-Up")
    btn:SetPushedAtlas(PREFIX .. name .. "-Down")
    btn:SetDisabledAtlas(PREFIX .. name .. "-Disabled")
    btn:SetHighlightAtlas(PREFIX .. name .. "-Mouseover")
end

local function SetVertexColorAll(btn, r, g, b)
    for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" }) do
        local t = btn[getter](btn)
        if t then t:SetVertexColor(r, g, b) end
    end
end

-- MainMenuBarMicroButtonMixin:SetPushed and SetNormal, and the Character
-- button's own pair, on the twin's regions.
local function SetPushed(btn)
    btn.Background:Hide()
    btn.PushedBackground:Show()
    btn:SetButtonState("PUSHED", true)
    if btn.textureName then
        btn:SetHighlightAtlas(PREFIX .. btn.textureName .. "-Down", "ADD")
        btn:GetHighlightTexture():SetAlpha(0.5)
    end
    if btn.Portrait then
        btn.PushedShadow:Show()
        btn.PortraitMask:ClearAllPoints()
        btn.PortraitMask:SetPoint("CENTER", 2, -2)
        btn.Portrait:ClearAllPoints()
        btn.Portrait:SetPoint("TOPLEFT", 7, -7)
        btn.Portrait:SetPoint("BOTTOMRIGHT", -6, 5)
    end
end

local function SetNormal(btn)
    btn:SetButtonState("NORMAL")
    if btn.textureName then
        btn:SetHighlightAtlas(PREFIX .. btn.textureName .. "-Mouseover", "BLEND")
        btn:GetHighlightTexture():SetAlpha(1)
    end
    btn.Background:Show()
    btn.PushedBackground:Hide()
    if btn.Portrait then
        btn.PushedShadow:Hide()
        btn.PortraitMask:ClearAllPoints()
        btn.PortraitMask:SetPoint("CENTER", 0, 0)
        btn.Portrait:ClearAllPoints()
        btn.Portrait:SetPoint("TOPLEFT", 7, -7)
        btn.Portrait:SetPoint("BOTTOMRIGHT", -7, 7)
    end
end

-- The regions every micro button carries, then the three buttons with more.
local function BuildArt(btn, blizz)
    local bg = texture(btn, "Background", "BACKGROUND")
    bg:SetAtlas(PREFIX .. "ButtonBG-Up", true)
    bg:SetPoint("CENTER")
    local pushedBg = texture(btn, "PushedBackground", "BACKGROUND")
    pushedBg:SetAtlas(PREFIX .. "ButtonBG-Down", true)
    pushedBg:SetPoint("CENTER")
    pushedBg:Hide()

    local flash = texture(btn, "FlashBorder", "OVERLAY")
    flash:SetAllPoints()
    flash:SetAtlas(PREFIX .. "Highlightalert")
    flash:SetBlendMode("BLEND")
    flash:Hide()

    local content = blizz.FlashContent
    if content then
        local layer = content:GetDrawLayer()
        local fc = texture(btn, "FlashContent", layer)
        fc:SetAtlas(content:GetAtlas(), true)
        fc:SetBlendMode("BLEND")
        fc:SetPoint("CENTER")
        fc:Hide()
    end

    -- MainMenuBarMicroButtonNotificationTemplate: frame level 100, the
    -- communities pip above the button's top edge.
    local note = CreateFrame("Frame", nil, btn)
    note:SetAllPoints()
    note:SetFrameLevel(btn:GetFrameLevel() + 50)
    local pip = note:CreateTexture(nil, "OVERLAY")
    pip:SetAtlas(PREFIX .. "Communities-Icon-Notification")
    pip:SetSize(21, 21)
    pip:SetPoint("TOP", note, "TOP", 0, 6)
    note:Hide()
    btn.NotificationOverlay = note

    if blizz == CharacterMicroButton then
        local shadow = texture(btn, "Shadow", "BORDER")
        shadow:SetAtlas(PREFIX .. "Portrait-Shadow", true)
        shadow:SetPoint("CENTER")
        local portrait = texture(btn, "Portrait", "ARTWORK")
        portrait:SetPoint("TOPLEFT", 7, -7)
        portrait:SetPoint("BOTTOMRIGHT", -7, 7)
        portrait:SetTexCoord(0.2, 0.8, 0.0666, 0.9)
        local mask = btn:CreateMaskTexture(nil, "OVERLAY")
        mask:SetAtlas(PREFIX .. "Portrait-Mask")
        mask:SetSize(35, 65)
        mask:SetPoint("CENTER")
        portrait:AddMaskTexture(mask)
        btn.PortraitMask = mask
        local pushedShadow = texture(btn, "PushedShadow", "OVERLAY")
        pushedShadow:SetAtlas(PREFIX .. "Portrait-Down", true)
        pushedShadow:SetPoint("CENTER", 1, -4)
        pushedShadow:Hide()
    elseif blizz == GuildMicroButton then
        local emblem = texture(btn, "Emblem", "OVERLAY")
        emblem:SetSize(12, 14)
        emblem:SetPoint("CENTER", 0, 2)
        local highlight = texture(btn, "HighlightEmblem", "HIGHLIGHT", 5)
        highlight:SetSize(12, 14)
        highlight:SetPoint("CENTER", 0, 2)
    elseif blizz == MainMenuMicroButton then
        local bar = texture(btn, "PerformanceBar", "OVERLAY")
        bar:SetTexture("Interface\\MainMenuBar\\UI-MainMenuBar-PerformanceBar")
        bar:SetSize(19, 39)
        bar:SetPoint("BOTTOM", btn, "BOTTOM", 0, -2)
    end
end

--------------------------------------------------------------------------------
-- The sync
--------------------------------------------------------------------------------

local function CopyTexture(dst, src)
    if not (dst and src) then return end
    local atlas = src:GetAtlas()
    if atlas then
        dst:SetAtlas(atlas)
    else
        dst:SetTexture(src:GetTexture())
        dst:SetTexCoord(src:GetTexCoord())
    end
    dst:SetVertexColor(src:GetVertexColor())
    dst:SetShown(src:IsShown())
end

local function Sync(btn)
    local blizz = btn.blizz
    if blizz ~= MainMenuMicroButton then
        local name = blizz.textureName
        if name and name ~= btn.textureName then LoadTextures(btn, name) end
        local normal = blizz:GetNormalTexture()
        if normal then SetVertexColorAll(btn, normal:GetVertexColor()) end
    end

    -- The twin stays enabled, since Disable on a protected button is blocked
    -- in lockdown: a disabled Blizzard button shows as its disabled art, and
    -- the forwarded click lands on that button, which ignores it.
    local enabled = blizz:IsEnabled()
    btn.mirrorEnabled = enabled
    btn:SetAlpha(blizz:GetAlpha())
    if btn.textureName then
        btn:SetNormalAtlas(PREFIX .. btn.textureName .. (enabled and "-Up" or "-Disabled"))
    end
    if enabled and blizz:GetButtonState() == "PUSHED" then
        SetPushed(btn)
    else
        SetNormal(btn)
    end

    local note = blizz.NotificationOverlay
    btn.NotificationOverlay:SetShown(note and note:IsShown() or false)
    if btn.Portrait and blizz.Portrait then
        btn.Portrait:SetDesaturated(blizz.Portrait:IsDesaturated())
    end
    if btn.Emblem then
        CopyTexture(btn.Emblem, blizz.Emblem)
        CopyTexture(btn.HighlightEmblem, blizz.HighlightEmblem)
    end
end

function Micro.SyncAll()
    for _, btn in ipairs(buttons) do Sync(btn) end
end

-- Which twins draw: Blizzard's shown flag, which its own layout and the game
-- rules set. Read when the strip lays out, out of combat.
function Micro.Visible()
    local list = {}
    for _, btn in ipairs(buttons) do
        if btn.blizz:IsShown() then list[#list + 1] = btn end
    end
    return list
end

--------------------------------------------------------------------------------
-- The game menu button's stream and latency art
--------------------------------------------------------------------------------
-- MainMenuMicroButtonMixin:OnUpdate, once a second on a ticker.

local function UpdateMainMenu(btn)
    local status = GetFileStreamingStatus()
    if status == 0 then
        status = (GetBackgroundLoadingStatus() ~= 0) and 1 or 0
    end
    local kit = "GameMenu"
    if status == 1 then
        kit = "StreamDLGreen"
    elseif status == 2 then
        kit = "StreamDLYellow"
    elseif status == 3 then
        kit = "StreamDLRed"
    end
    btn.textureName = kit
    local enabled = btn.mirrorEnabled ~= false
    btn:SetNormalAtlas(PREFIX .. kit .. (enabled and "-Up" or (status == 0 and "-Disabled" or "-Up")))
    btn:SetPushedAtlas(PREFIX .. kit .. "-Down")
    btn:SetDisabledAtlas(PREFIX .. kit .. ((status == 0) and "-Disabled" or "-Up"))
    if btn:GetButtonState() == "NORMAL" then
        btn:SetHighlightAtlas(PREFIX .. kit .. ((status == 0) and "-Mouseover" or "-Up"), "BLEND")
    else
        btn:SetHighlightAtlas(PREFIX .. kit .. "-Down", "ADD")
    end

    local _, _, home, world = GetNetStats()
    local latency = math.max(home or 0, world or 0)
    if latency > MEDIUM_LATENCY then
        btn.PerformanceBar:SetVertexColor(1, 0, 0)
    elseif latency > LOW_LATENCY then
        btn.PerformanceBar:SetVertexColor(1, 1, 0)
    else
        btn.PerformanceBar:SetVertexColor(0, 1, 0)
    end
    if btn.hover and MainMenuBarPerformanceBarFrame_OnEnter then
        btn.tooltipText = MainMenuMicroButton.tooltipText
        MainMenuBarPerformanceBarFrame_OnEnter(btn)
    end
end

--------------------------------------------------------------------------------
-- Scripts
--------------------------------------------------------------------------------

-- MainMenuBarMicroButtonMixin:EvaluateTooltipVisibility, on the twin.
local function ShowTooltip(btn)
    local blizz = btn.blizz
    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
    GameTooltip_SetTitle(GameTooltip, blizz.tooltipText)
    if not blizz:IsEnabled() then
        local text
        if blizz.factionGroup == "Neutral" then
            text = FEATURE_NOT_AVAILBLE_PANDAREN
        elseif blizz.minLevel then
            text = format(FEATURE_BECOMES_AVAILABLE_AT_LEVEL, blizz.minLevel)
        elseif blizz.disabledTooltip then
            text = GetValueOrCallFunction(blizz, "disabledTooltip")
        end
        if text then
            GameTooltip:AddLine(text, RED_FONT_COLOR.r, RED_FONT_COLOR.g, RED_FONT_COLOR.b, true)
        end
    end
    GameTooltip:Show()
end

local function OnEnter(btn)
    local normal = btn:GetNormalTexture()
    if normal then normal:SetAlpha(0) end
    if btn.blizz == MainMenuMicroButton then
        btn.hover = true
        UpdateMainMenu(btn)
        return
    end
    ShowTooltip(btn)
end

local function OnLeave(btn)
    btn.hover = nil
    GameTooltip:Hide()
    local normal = btn:GetNormalTexture()
    if normal then normal:SetAlpha(1) end
end

local function OnMouseDown(btn)
    if btn.blizz:IsEnabled() then SetPushed(btn) end
end

local function OnMouseUp(btn)
    -- The click's own UpdateMicroButtons has run by the next frame.
    C_Timer.After(0, function() Sync(btn) end)
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

-- The parent is the strip microbags.lua creates, a Camelot frame, so the
-- secure child protects only Camelot's own holders.
local function Twin(parent, blizzName)
    local blizz = _G[blizzName]
    if not blizz then return nil end
    local btn = CreateFrame("Button", "Camelot" .. blizzName, parent, "SecureActionButtonTemplate")
    btn:SetSize(Micro.WIDTH, Micro.HEIGHT)
    btn:SetMotionScriptsWhileDisabled(true)
    btn:RegisterForClicks("AnyUp")
    btn:SetAttribute("type", "click")
    btn:SetAttribute("clickbutton", blizz)
    -- The secure handler fires on key down when the player's cast-on-down
    -- setting is on, and a mouse click arrives as an up; pinned so the
    -- click always lands.
    btn:SetAttribute("useOnKeyDown", false)
    btn.blizz = blizz
    BuildArt(btn, blizz)
    if blizz.textureName then LoadTextures(btn, blizz.textureName) end
    btn:SetScript("OnEnter", OnEnter)
    btn:SetScript("OnLeave", OnLeave)
    btn:HookScript("OnMouseDown", OnMouseDown)
    btn:HookScript("OnMouseUp", OnMouseUp)
    byBlizzard[blizz] = btn
    return btn
end

local function HookBlizzard()
    hooksecurefunc("UpdateMicroButtons", Micro.SyncAll)
    hooksecurefunc("MicroButtonPulse", function(blizz, duration)
        local btn = byBlizzard[blizz]
        if not btn or (MainMenuMicroButton_AreAlertsEnabled and not MainMenuMicroButton_AreAlertsEnabled()) then
            return
        end
        UIFrameFlash(btn.FlashBorder, 1.0, 1.0, duration or -1, false, 0, 0, "camelotMicro")
        if btn.FlashContent then
            UIFrameFlash(btn.FlashContent, 1.0, 1.0, duration or -1, false, 0, 0, "camelotMicro")
        end
    end)
    hooksecurefunc("MicroButtonPulseStop", function(blizz)
        local btn = byBlizzard[blizz]
        if not btn then return end
        UIFrameFlashStop(btn.FlashBorder)
        if btn.FlashContent then UIFrameFlashStop(btn.FlashContent) end
    end)
    -- Forever's buttons announce their own changes (the beta's
    -- MainMenuBarMicroButton_OnLoad); the replica listens where they do.
    for blizz, btn in pairs(byBlizzard) do
        if blizz.RegisterCallback then
            for _, event in ipairs({ "OnEnable", "OnDisable", "OnNewNotification", "OnDismissedNotification" }) do
                -- A button whose registry lacks the event refuses it; the
                -- UpdateMicroButtons hook still covers that button.
                pcall(blizz.RegisterCallback, blizz, event, function() Sync(btn) end, btn)
            end
        end
    end
end

local function OnPortrait()
    local btn = byBlizzard[CharacterMicroButton or false]
    if btn and btn.Portrait then SetPortraitTexture(btn.Portrait, "player") end
end

--- Build the twins into the strip, once, out of combat.
function Micro.Build(strip)
    if #buttons > 0 then return end
    for _, name in ipairs(Micro.ORDER) do
        local btn = Twin(strip, name)
        if btn then buttons[#buttons + 1] = btn end
    end
    HookBlizzard()
    OnPortrait()
    Micro.SyncAll()

    local mainMenu = byBlizzard[MainMenuMicroButton or false]
    if mainMenu then
        UpdateMainMenu(mainMenu)
        C_Timer.NewTicker(1, function()
            if mainMenu:IsVisible() then UpdateMainMenu(mainMenu) end
        end)
    end

    local owner = ActionBars.OWNER .. ".micro"
    addon.Events.On(owner, "UNIT_PORTRAIT_UPDATE", function(_, unit)
        if unit == "player" then OnPortrait() end
    end)
    addon.Events.On(owner, "PORTRAITS_UPDATED", OnPortrait)
    addon.Events.On(owner, "PLAYER_ENTERING_WORLD", function()
        OnPortrait()
        Micro.SyncAll()
    end)
end

--- One line per twin for /camelot actionbars.
function Micro.Report(push)
    for _, btn in ipairs(buttons) do
        local blizz = btn.blizz
        push("    %-24s blizz shown %-5s enabled %-5s state %-7s twin shown %-5s %s",
            blizz:GetName(), tostring(blizz:IsShown()), tostring(blizz:IsEnabled()),
            tostring(blizz:GetButtonState()), tostring(btn:IsShown()), tostring(btn.textureName))
    end
end
