--------------------------------------------------------------------------------
-- forever/actionbars/gamepadmixins.lua
-- The globals gamepadframes.xml names in its mixin= attributes, for the
-- gamepad bar replica (gamepad.lua). They have to exist before the XML
-- parses, so this file loads before it and after mixins.lua, whose
-- CamelotActionButtonMixin the button template lists.
--
-- A slot is two frames. The visual button is Blizzard's gamepad button art
-- on the plain ActionButtonTemplate with Blizzard's button mixins and the
-- two Camelot mixins listed last, so each key here shadows the same key
-- from Blizzard's mixins on the instance, as mixins.lua does for the
-- standard bars. It carries no secure template and takes no mouse, so
-- Blizzard's expand, collapse and press styles move and resize it in a
-- fight as they do Blizzard's own. The click target is a secure action
-- button on ActionButtonTemplate at alpha 0, under a click layer beside the
-- bar, laid over its visual out of combat; a mouse press, drag, drop and
-- tooltip go through it to the visual, and Blizzard's own attribute handler
-- writes the flyout fields Forever's click path reads. Nothing is copied
-- from Blizzard's mixins. Each override names the function it replaces in
-- Blizzard_GamepadActionBars.
--
-- Two modes. An action button draws the action its storage slot holds on
-- the mirrored page, through CamelotActionButtonMixin, and a click on its
-- target casts it. A mirror button draws a copy of one Blizzard button (the
-- four reserved slots, the override bars) and has no click target.
--------------------------------------------------------------------------------

local _, addon = ...

local function Events()
    return addon.ActionBars.Events
end

local function queue(fn, key)
    addon.Events.RunOutOfCombat(fn, key)
end

local function nop() end

-- A boolean that is plain and true (mixins.lua).
local function plainTrue(v)
    if type(v) ~= "boolean" then return false end
    if issecretvalue(v) then return false end
    return v
end

local function plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

local function constants()
    return Constants.GamepadActionBarConstants
end

--------------------------------------------------------------------------------
-- The button
--------------------------------------------------------------------------------

CamelotGamepadButtonMixin = {
    -- The page the button draws, before the page unit sets one: every
    -- attribute written during the load runs UpdateAction through
    -- OnAttributeChanged, and CalculateAction reads this.
    page = 1,
}

-- Replaces GamepadActionBarStandardButtonMixin:OnLoad. Blizzard's runs the
-- two gamepad loads, then ActionBarButtonMixin_OnLoad, which registers the
-- button with Blizzard's event frames; the Camelot load stands in. Its
-- attribute writes land on this plain button and do nothing: the click
-- target writes its own. The mouse goes off last, since a SetScript turns
-- it back on.
function CamelotGamepadButtonMixin:OnLoad()
    GamepadActionBarButtonFlyoutMixin.OnLoad(self)
    GamepadActionBarButtonMixin.OnLoad(self)
    CamelotActionButtonMixin.ActionBarButtonMixin_OnLoad(self)
    -- Blizzard's own line: the override file's art pass must not run again.
    self.SetButtonArt = nop
    -- Blizzard's bar hides the keybind text at its own load; a gamepad
    -- button never draws one.
    self.HotKey:Hide()
    self.HotKey.Show = nop
    self:EnableMouse(false)
end

-- Replaces GamepadActionBarButtonFlyoutMixin:CalculateAction. A reserved
-- slot, a mirror, or a button the bar has not numbered yet (the attribute
-- writes of the load run before the bar's load) gives 0, as Blizzard's
-- reserved buttons do; the rest is the storage index of the slot on the
-- mirrored page.
function CamelotGamepadButtonMixin:CalculateAction()
    local slot = self.pageUnitSlotID
    if self.mirrorMode or not slot then return 0 end
    local util = GamepadActionBarBindingUtil
    if util.IsReservedPageUnitSlotID(slot) then return 0 end
    return util.GetGamepadStorageSlotIndexFromPageAndPageUnitSlotID(self.page, slot) or 0
end

--- Draw the slot's action on this page, and give the click target the same
--- index. The attribute write waits for regen in a fight: until then a
--- mouse click casts the previous page's slot.
function CamelotGamepadButtonMixin:SetPage(page)
    if self.mirrorMode then return end
    self.page = page
    self:UpdateAction(true)
    local click = self.click
    if not click then return end
    local action = self:CalculateAction()
    local function write()
        if click:GetAttribute("action") ~= action then
            click:SetAttribute("action", action)
        end
    end
    if InCombatLockdown() then
        queue(write, "camelotActionBars.gamepad.action." .. click:GetName())
    else
        write()
    end
end

--- The click target's popup is Blizzard's attribute handler's to write
--- (CamelotGamepadClickMixin), which reads the slot on every attribute
--- change; this attribute changes when the slot's kind does, so a flyout
--- dragged into or out of the slot runs the handler again.
function CamelotGamepadButtonMixin:SyncClickFlyout()
    local click = self.click
    if not click then return end
    local value = self.isFlyoutAction and 1 or 0
    local function write()
        if click:GetAttribute("camelotFlyout") ~= value then
            click:SetAttribute("camelotFlyout", value)
        end
    end
    if InCombatLockdown() then
        queue(write, "camelotActionBars.gamepad.flyout." .. click:GetName())
    else
        write()
    end
end

-- Replaces GamepadActionBarButtonFlyoutMixin:UpdateFlyoutActionInfo, which
-- registers five events on the button and hands a closure to Blizzard's
-- SpellEventListener. The fields alone are kept; gamepad.lua forwards those
-- events to every flyout button, and a flyout draws its own texture
-- rather than its one known spell's.
function CamelotGamepadButtonMixin:UpdateFlyoutActionInfo(isFlyoutAction, flyoutID)
    self.isFlyoutAction = isFlyoutAction
    self.flyoutID = flyoutID
    self.spellID = nil
end

-- Replaces GamepadActionBarButtonFlyoutMixin:UpdateAction, whose last line
-- calls Blizzard's ActionBarActionButtonMixin.UpdateAction by table and so
-- skips the Camelot override; the flyout detection is restated above the
-- Camelot call.
function CamelotGamepadButtonMixin:UpdateAction(force)
    if self.mirrorMode then return end
    local action = self:CalculateAction()
    if not force and self.action == action then return end
    local isFlyoutAction, flyoutID = false, nil
    if action and action > 0 then
        local actionType, id = GetActionInfo(action)
        if actionType == "flyout" then
            isFlyoutAction, flyoutID = true, id
        end
    end
    self:UpdateFlyoutActionInfo(isFlyoutAction, flyoutID)
    self:SyncClickFlyout()
    CamelotActionButtonMixin.UpdateAction(self, force)
end

-- Replaces GamepadActionBarButtonFlyoutMixin:Update: the Camelot pass, then
-- the flyout's own icon.
function CamelotGamepadButtonMixin:Update(...)
    CamelotActionButtonMixin.Update(self, ...)
    self:UpdateFlyoutActionIcon()
end

-- Replaces GamepadActionBarButtonFlyoutMixin:UpdateCooldown, whose path is
-- the numeric ActionButton_UpdateCooldown.
function CamelotGamepadButtonMixin:UpdateCooldown()
    self:UpdateCooldownFromDurations()
end

--- The five events Blizzard registers on a flyout button, forwarded by
--- gamepad.lua to every button whose action is a flyout.
function CamelotGamepadButtonMixin:OnFlyoutEvent(event, ...)
    if self.mirrorMode or not self.isFlyoutAction then return end
    if event == "UNIT_AURA" then
        self:UpdateFlyoutActionIcon()
        self:UpdateState()
    elseif event == "UNIT_POWER_UPDATE" then
        self:UpdateUsable()
    elseif event == "SPELL_FLYOUT_UPDATE" then
        if self.flyoutID == (...) then self:UpdateAction(true) end
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        self:UpdateCooldownFromDurations()
    elseif event == "BAG_UPDATE" then
        self:UpdateCount()
        self:UpdateUsable()
    end
end

-- Replaces GamepadActionBarStandardButtonMixin:OnEvent: the Camelot
-- handler, then the range verdict onto the art and the form change onto a
-- flyout's icon. A mirror draws nothing from events.
function CamelotGamepadButtonMixin:OnEvent(event, ...)
    if self.mirrorMode then return end
    CamelotActionButtonMixin.OnEvent(self, event, ...)
    if event == "ACTION_RANGE_CHECK_UPDATE" then
        local _, inRange, checksRange = ...
        self:RefreshRange(plainTrue(checksRange), plainTrue(inRange))
    elseif event == "UPDATE_SHAPESHIFT_FORM" then
        self:UpdateFlyoutActionIcon()
    end
end
CamelotGamepadButtonMixin.ActionBarActionButtonDerivedMixin_OnEvent = CamelotGamepadButtonMixin.OnEvent

-- Extends GamepadActionBarButtonFlyoutMixin:ReapplyStyle, the radial's call
-- on detach, which lays the bar out again: the click targets follow.
function CamelotGamepadButtonMixin:ReapplyStyle()
    GamepadActionBarButtonFlyoutMixin.ReapplyStyle(self)
    local bar = self.parentActionBar
    if bar and bar.RefreshClickLayout then bar:RefreshClickLayout() end
end

-- Replaces ActionBarActionButtonMixin:OnShow and OnHide, which the template
-- names: a mirror draws from its source alone, and Blizzard's show would
-- run Update on it and clear the copied icon.
function CamelotGamepadButtonMixin:OnShow()
    if self.mirrorMode then return end
    ActionBarActionButtonMixin.OnShow(self)
end

function CamelotGamepadButtonMixin:OnHide()
    if self.mirrorMode then return end
    ActionBarActionButtonMixin.OnHide(self)
end

-- Replaces GamepadActionBarStandardButtonMixin:OnDragStart, reached from
-- the click target.
function CamelotGamepadButtonMixin:OnDragStart()
    if self.mirrorMode then return end
    ActionBarActionButtonMixin.OnDragStart(self)
end

-- Replaces ActionBarActionButtonMixin:HasAction. A mirror stands for a
-- reserved slot or an override bar's button, which makes its bar non-empty;
-- an action button with no slot yet has none.
function CamelotGamepadButtonMixin:HasAction()
    if self.mirrorMode then return true end
    local action = self.action
    if not action or action == 0 then return false end
    return C_ActionBar.HasAction(action)
end

--------------------------------------------------------------------------------
-- Mirror mode
--------------------------------------------------------------------------------

-- Blizzard's backdrop under a reserved slot's special icon
-- (MainActionBarFrame.lua, SetupNonBindableSlotBackdrop).
local function AddBackdrop(button)
    if button.MirrorBackdrop then return end
    local backdrop = button:CreateTexture()
    backdrop:AddMaskTexture(button.CircleMask)
    backdrop:SetAllPoints(button.SlotArt)
    backdrop:SetColorTexture(0, 0, 0, 1)
    backdrop:SetDrawLayer("BACKGROUND", 0)
    button.MirrorBackdrop = backdrop
end

--- Turn the button into a mirror, once: no action, nothing of Blizzard's
--- drawn from events. A mirror bar's buttons and the reserved slots get no
--- click target at the bar's load, so nothing secure is touched.
function CamelotGamepadButtonMixin:ArmMirror(reserved)
    if self.mirrorMode then return end
    self.mirrorMode = true
    self.mirrorCache = {}
    if self.action then
        Events().UnwatchAction(self, self.action)
    end
    C_ActionBar.UnregisterActionUIButton(self)
    self.icon:SetTexture(nil)
    self.icon:Hide()
    self.Count:SetText("")
    self:SetChecked(false)
    ClearActionButtonCooldowns(self.cooldown, self.chargeCooldown, self.lossOfControlCooldown)
    self.SpecialActionIcon:Show()
    -- Blizzard's layering for a slot drawn through the special icon
    -- (StaticOverrideActionBar.lua, SetUpDefaultActionButton; a reserved
    -- slot's backdrop goes under it at 0): the icon at sublevel 1 and the
    -- overlay ring at 2, under the icon's own masks.
    self.SpecialActionIcon:SetDrawLayer("BACKGROUND", 1)
    local overlay = self:CreateTexture()
    overlay:SetDrawLayer("BACKGROUND", 2)
    overlay:SetAllPoints(self.SpecialActionIcon)
    overlay:AddMaskTexture(self.CircleMask)
    overlay:AddMaskTexture(self.SquareMask)
    overlay:Hide()
    self.IconOverlay = overlay
    if reserved then
        AddBackdrop(self)
        -- The interact slot's attack flash, Blizzard's square flash
        -- over-scaled under the circle mask (SetupNonBindableInteract).
        if self.pageUnitSlotID == 5 then
            self.Flash:ClearAllPoints()
            self.Flash:SetPoint("CENTER")
            self.Flash:SetScale(1.5)
        end
    end
end

--- The Blizzard button this mirror copies, or nil.
function CamelotGamepadButtonMixin:SetMirror(source)
    self.mirror = source
    if source then
        self:SyncMirror()
    else
        self.SpecialActionIcon:Hide()
        self.icon:Hide()
    end
end

local function copyTexture(cache, key, dst, src)
    local atlas = plain(src:GetAtlas())
    if atlas then
        if cache[key] ~= atlas then
            cache[key] = atlas
            dst:SetAtlas(atlas)
        end
    else
        local texture = plain(src:GetTexture())
        if cache[key] ~= texture then
            cache[key] = texture
            dst:SetTexture(texture)
        end
    end
    local a, b, c, d, e, f, g, h = src:GetTexCoord()
    if plain(a) ~= nil then
        local coords = cache[key .. "Coords"]
        if not coords or coords[1] ~= a or coords[2] ~= b or coords[3] ~= c or coords[4] ~= d
            or coords[5] ~= e or coords[6] ~= f or coords[7] ~= g or coords[8] ~= h then
            cache[key .. "Coords"] = { a, b, c, d, e, f, g, h }
            dst:SetTexCoord(a, b, c, d, e, f, g, h)
        end
    end
end

-- The special icon's anchors, as Blizzard moves them per reserved slot:
-- the same points against this button.
local function copyAnchors(cache, dst, src, owner)
    local n = src:GetNumPoints()
    local sig = tostring(n)
    local points = {}
    for i = 1, n do
        local point, _, relativePoint, x, y = src:GetPoint(i)
        points[i] = { point, relativePoint, x or 0, y or 0 }
        sig = sig .. ":" .. tostring(point) .. tostring(relativePoint) .. tostring(x) .. "," .. tostring(y)
    end
    if cache.anchors == sig then return end
    cache.anchors = sig
    dst:ClearAllPoints()
    if n == 0 then
        dst:SetAllPoints(owner)
        return
    end
    for _, p in ipairs(points) do
        dst:SetPoint(p[1], owner, p[2], p[3], p[4])
    end
end

local function copyShown(cache, key, dst, src)
    if not (dst and src) then return end
    local shown = src:IsShown() and true or false
    if cache[key] ~= shown then
        cache[key] = shown
        dst:SetShown(shown)
    end
end

--- Copy the source button's look: icon, special icon, overlays, flash,
--- checked and enabled states. Every read is a plain getter on the source;
--- a value that reads secret is skipped; nothing is written on no change.
function CamelotGamepadButtonMixin:SyncMirror()
    local src = self.mirror
    if not src then return end
    local cache = self.mirrorCache

    local icon = src.icon
    if icon then
        copyTexture(cache, "icon", self.icon, icon)
        local alpha = plain(icon:GetAlpha())
        copyShown(cache, "iconShown", self.icon, icon)
        if alpha ~= nil and cache.iconAlpha ~= alpha then
            cache.iconAlpha = alpha
            self.icon:SetAlpha(alpha)
        end
        local desaturated = plain(icon:IsDesaturated()) and true or false
        if cache.iconDesaturated ~= desaturated then
            cache.iconDesaturated = desaturated
            self.icon:SetDesaturated(desaturated)
        end
    end

    local special = src.SpecialActionIcon
    if special then
        local unit = self.portraitUnit
        if unit and plain(special:GetAtlas()) == nil then
            -- A portrait slot: SetPortraitTexture leaves nothing GetTexture
            -- can copy, so the mirror draws the unit itself, every sync,
            -- since the same token can name another unit next time.
            SetPortraitTexture(self.SpecialActionIcon, unit)
            cache.special = nil
            cache.specialCoords = nil
        else
            copyTexture(cache, "special", self.SpecialActionIcon, special)
        end
        copyAnchors(cache, self.SpecialActionIcon, special, self)
        copyShown(cache, "specialShown", self.SpecialActionIcon, special)
        local desaturated = plain(special:IsDesaturated()) and true or false
        if cache.specialDesaturated ~= desaturated then
            cache.specialDesaturated = desaturated
            self.SpecialActionIcon:SetDesaturated(desaturated)
        end
    end

    copyShown(cache, "permabound", self.PermaboundOverlay, src.PermaboundOverlay)
    if src.IconOverlay and self.IconOverlay then
        copyTexture(cache, "iconOverlay", self.IconOverlay, src.IconOverlay)
        copyShown(cache, "iconOverlayShown", self.IconOverlay, src.IconOverlay)
    end
    copyShown(cache, "flash", self.Flash, src.Flash)

    -- A targeting bar dims a disabled slot to 0.3 (StaticOverrideActionBar.lua,
    -- SetButtonEnabled); the enabled state alone would not show it.
    local alpha = plain(src:GetAlpha())
    if alpha ~= nil and cache.alpha ~= alpha then
        cache.alpha = alpha
        self:SetAlpha(alpha)
    end

    local checked = plain(src:GetChecked()) and true or false
    if cache.checked ~= checked then
        cache.checked = checked
        self:SetChecked(checked)
    end

    local enabled = plain(src:IsEnabled()) and true or false
    if cache.enabled ~= enabled then
        cache.enabled = enabled
        self:SetEnabled(enabled)
    end
end

--------------------------------------------------------------------------------
-- The bar
--------------------------------------------------------------------------------

CamelotGamepadBarMixin = {}

--- The frame Blizzard's bar code reads its five settings off: the page
--- unit's parent, the Face in gamepad.lua. Nil before the owner is set.
function CamelotGamepadBarMixin:Face()
    local unit = self.pagingUnitOwner
    return unit and unit:GetParent() or nil
end

-- The bar's resting frame level, one above its anchor's: Blizzard's bar
-- sits at 4 and goes to 5 while active (ActionBar.lua), and this one keeps
-- the same step above whatever level the holder has.
local function BaseLevel(bar)
    local parent = bar:GetParent()
    return (parent and parent:GetFrameLevel() or 0) + 1
end

-- Extends GamepadActionBarMixin:OnLoad, which applies the collapsed style,
-- registers the soft enemy event and wires the eight buttons; then each
-- button takes its slot id from the bar's slotOffset KeyValue, and an
-- action bar gets its click layer: one secure target per bindable slot
-- under a frame beside this bar on the anchor, never on the bar itself, so
-- the bar and its buttons stay unprotected and Blizzard's styles can size
-- them in a fight (a protected child, or a protected frame anchored to it,
-- makes a frame protected). A mirror bar arms every button and gets no
-- targets; the prompts stay hidden until the bar expands with Button
-- Prompts on.
function CamelotGamepadBarMixin:OnLoad()
    GamepadActionBarMixin.OnLoad(self)
    -- Blizzard's empty slot art is an atlas per button index and shape with
    -- the glyph baked in (ActionBarButton.lua, the texture sets). The
    -- collapsed style reads it before InitActionButtons numbers the
    -- buttons, so every button read index 1: the dpad-left square on the
    -- whole left group, no circle art at all. The expand, collapse and
    -- press styles read it again; the first highlight is frames away, so
    -- once more now.
    self:UpdateButtonsEmptySlotBackgroundTexture()
    local offset = tonumber(self.slotOffset) or 0
    local layer
    if not self.isMirror then
        local anchor = self:GetParent()
        layer = CreateFrame("Frame", nil, anchor)
        layer:SetSize(1, 1)
        layer:SetPoint("CENTER", anchor, "CENTER")
        self.clickLayer = layer
    end
    for i, button in ipairs(self.actionButtons) do
        local slot = offset + i
        button:SetGamepadPageUnitSlotID(slot)
        button.anchorKey = self.anchorKey
        if self.isMirror then
            button:ArmMirror(false)
        else
            if not GamepadActionBarBindingUtil.IsReservedPageUnitSlotID(slot) then
                local click = CreateFrame("CheckButton", self:GetName() .. "Click" .. i, layer,
                    "CamelotGamepadClickTemplate")
                click:Arm()
                click.visual = button
                button.click = click
            end
            button:UpdateAction(true)
        end
    end
    self:HideButtonIcons()
    self:RefreshClickLayout()
end

--- Whether the settings ask for the focus background.
function CamelotGamepadBarMixin:HighlightEnabled()
    local face = self:Face()
    return face ~= nil and face.showHighlight ~= false
end

-- Replaces GamepadActionBarMixin:ShowHighlight, which returns early while
-- its usable function says no and reads the settings off the page unit's
-- parent: the frame level up, the focus background, Blizzard's expanded
-- style while Expand is on (the collapsed one back once it is turned off),
-- the prompts with it while Button Prompts is on too, and the click
-- targets over the moved buttons. The styles are Blizzard's own, on plain
-- buttons.
function CamelotGamepadBarMixin:ShowHighlight()
    self.highlighted = true
    local face = self:Face() or {}
    self:SetFrameLevel(BaseLevel(self) + 1)
    self.BackgroundFocus:SetShown(self:HighlightEnabled())
    local expand = face.shouldExpand == true
    if expand then
        self:ExpandActionButtons()
        self.actionBarScaledUp = true
    elseif self.actionBarScaledUp then
        self:CollapseActionButtons()
        self.actionBarScaledUp = false
    end
    if expand and face.showButtonIcons == true then
        self:ShowButtonIcons()
    else
        self:HideButtonIcons()
    end
    self:RefreshClickLayout()
end

-- Replaces GamepadActionBarMixin:HideHighlight: the same back, and the
-- click targets over the collapsed buttons.
function CamelotGamepadBarMixin:HideHighlight()
    self.highlighted = false
    self:HideButtonIcons()
    self:SetFrameLevel(BaseLevel(self))
    self.BackgroundFocus:Hide()
    if self.actionBarScaledUp then
        self:CollapseActionButtons()
        self.actionBarScaledUp = false
    end
    self:RefreshClickLayout()
end

--- The highlight again after a setting changes.
function CamelotGamepadBarMixin:RefreshHighlight()
    if self.highlighted then
        self:ShowHighlight()
    else
        self:HideHighlight()
    end
end

--- Each click target sized and placed over its visual, out of combat; in
--- a fight the pass waits for regen and the targets keep the last layout,
--- so a mouse click there lands where the button stood before the fight.
--- The visual's point is the one Blizzard's style set, CENTER on this bar;
--- a pushed button is read as if released.
function CamelotGamepadBarMixin:RefreshClickLayout()
    local layer = self.clickLayer
    if not layer then return end
    if InCombatLockdown() then
        queue(function() self:RefreshClickLayout() end,
            "camelotActionBars.gamepad.click." .. self:GetName())
        return
    end
    local util = GamepadActionBarStyleUtil
    for _, button in ipairs(self.actionButtons) do
        local click = button.click
        if click then
            local size = button:GetWidth()
            local _, relativeTo, _, x, y = button:GetPoint(1)
            if relativeTo == self then
                x, y = x or 0, y or 0
                if button:GetButtonState() == "PUSHED" then
                    size = size - util.PUSHED_BUTTON_SIZE_OFFSET
                    x = x - util.PUSHED_BUTTON_ANCHOR_OFFSET.x
                    y = y - util.PUSHED_BUTTON_ANCHOR_OFFSET.y
                end
                click:SetSize(size, size)
                click:ClearAllPoints()
                click:SetPoint("CENTER", layer, "CENTER", x, y)
            end
        end
    end
end

--- Whether the bar draws: Blizzard's RefreshActionBarVisibility rules on
--- the page unit's mirrored state and the settings on its parent.
function CamelotGamepadBarMixin:ShouldShow()
    local unit = self.pagingUnitOwner
    if not unit then return false end
    local parent = unit:GetParent()
    local compact = unit:ShouldUseCompactLayout()
    if self.isMirror then
        if not self.mirrorSource then return false end
        return not compact or unit:GetActiveBar() == self
    end
    if unit:IsAnchorOverridden(self.anchorKey) then return false end
    if unit:GetCurrentPage() == constants().GAMEPAD_ACTION_BAR_PAGE_UNIT_SPECIAL_PAGE_INDEX then
        return false
    end
    if compact and unit:GetActiveBar() ~= self then return false end
    if parent and parent.showEmptyBars == false and self:IsBarEmpty() then return false end
    return true
end

-- Replaces GamepadActionBarMixin:RefreshActionBarVisibility. The bar and
-- its buttons are plain frames, so the shown state lands at once, in a
-- fight too; the click layer is protected, so its state waits for regen
-- there, and until then a hidden bar's targets still take a click.
function CamelotGamepadBarMixin:RefreshActionBarVisibility()
    local shown = self:ShouldShow()
    self:SetShown(shown)
    local layer = self.clickLayer
    if not layer or (layer:IsShown() and true or false) == shown then return end
    if InCombatLockdown() then
        queue(function() self:RefreshActionBarVisibility() end,
            "camelotActionBars.gamepad.shown." .. self:GetName())
    else
        layer:SetShown(shown)
    end
end

--- The page every action button draws.
function CamelotGamepadBarMixin:SetPage(page)
    for _, button in ipairs(self.actionButtons) do
        button:SetPage(page)
    end
end

-- The slots a targeting bar draws with SetPortraitTexture, by logical
-- index (1 to 4 the dpad, 5 to 8 the face buttons;
-- FriendlyTargetingActionBar.lua, HostileTargetingActionBar.lua), and the
-- CVar under which the bar exchanges its two groups
-- (StaticOverrideActionBar.lua, ShouldSwapLeftAndRightButtons). The party
-- units draw under party targeting alone; under raid targeting the same
-- slots carry atlases, which the sync copies instead.
local PORTRAIT_SLOTS = {
    friendlyTargetingBar = {
        swapCVar = "GamepadSwapFriendlyTargetActions",
        units = { [1] = "party4", [2] = "party1", [3] = "party2", [4] = "party3", [5] = "pet",
            [7] = "targettarget", [8] = "player" },
    },
    hostileTargetingBar = {
        swapCVar = "GamepadSwapHostileTargetActions",
        units = { [7] = "targettarget" },
    },
}

--- A mirror bar's source: the Blizzard bar whose buttons it copies, and
--- its name in the page unit's actionBars, which says which of its slots
--- are portraits.
function CamelotGamepadBarMixin:SetSource(source, name)
    self.mirrorSource = source
    local portraits = source and name and PORTRAIT_SLOTS[name] or nil
    local swapped = portraits and C_CVar.GetCVarBool(portraits.swapCVar) or false
    for i, button in ipairs(self.actionButtons) do
        local unit
        if portraits then
            local logical = i
            if swapped then logical = i > 4 and i - 4 or i + 4 end
            unit = portraits.units[logical]
        end
        button.portraitUnit = unit
        button:SetMirror(source and source.actionButtons and source.actionButtons[i] or nil)
    end
end

--- The active icon set changed: the slot art and the prompts again.
function CamelotGamepadBarMixin:RefreshInputIconSet()
    self:UpdateButtonsEmptySlotBackgroundTexture()
    for _, button in ipairs(self.actionButtons) do
        if button.ButtonIcon then button.ButtonIcon:Refresh() end
    end
end

--- Copy every mirror's look again.
function CamelotGamepadBarMixin:SyncMirrors()
    for _, button in ipairs(self.actionButtons) do
        if button.mirror then button:SyncMirror() end
    end
end

--- The pushed state and Blizzard's pressed geometry (ApplyPressedStyle:
--- smaller and a step down) on button `index`, from the key the watcher
--- reads (bars.lua's rule for a native key).
function CamelotGamepadBarMixin:SetPushed(index, down)
    local button = self.actionButtons[index]
    if not button then return end
    -- Blizzard's PressActionButton clicks an enabled button alone, so a
    -- disabled targeting slot keeps still; a release always lands.
    if down and not button:IsEnabled() then return end
    button.keyDown = down or nil
    if down then
        if button:GetButtonState() == "NORMAL" then
            button:SetButtonState("PUSHED")
        end
    elseif button:GetButtonState() == "PUSHED" then
        button:SetButtonState("NORMAL")
    end
    button:ApplyPressedStyle(down)
end

--- Every pushed state cleared, when the active bar changes.
function CamelotGamepadBarMixin:ClearPushed()
    for _, button in ipairs(self.actionButtons) do
        button.keyDown = nil
        if button:GetButtonState() == "PUSHED" then
            button:SetButtonState("NORMAL")
            button:ApplyPressedStyle(false)
        end
    end
end

-- Replaces GamepadActionBarMixin:OnEvent: the soft enemy change refreshes
-- the action buttons' usable state; a mirror has none.
function CamelotGamepadBarMixin:OnEvent(event)
    if event == "PLAYER_SOFT_ENEMY_CHANGED" then
        for _, button in ipairs(self.actionButtons) do
            if not button.mirrorMode then button:UpdateUsable() end
        end
    end
end

--------------------------------------------------------------------------------
-- The click target
--------------------------------------------------------------------------------
-- One per bindable slot, a child of the bar's click layer, the one frame of
-- a slot the mouse reaches: a CheckButton on ActionButtonTemplate and
-- SecureActionButtonTemplate at alpha 0, so none of the template's art
-- shows. Its attributes are the standard replica's (mixins.lua,
-- ActionBarButtonMixin_OnLoad): type action, the key-down release off, so a
-- mouse click casts on the release; the action index is written by the
-- visual's SetPage.
--
-- Forever's SECURE_ACTIONS.action reads the flyout popup off the button
-- (`self.popup or SpellFlyout`, SecureTemplates.lua of the 1.60.1 build;
-- retail's names the global). A field written by a Camelot call is
-- tainted, and the secure click that reads it ends in a forbidden
-- UseAction: the first mouse click on these bars did. So nothing here
-- writes popup or popupDirection. ActionButtonTemplate's OnLoad and
-- OnAttributeChanged stay Blizzard's, and its UpdateFlyout, run securely on
-- every attribute change, resolves the action attribute and writes both
-- fields from what the slot holds and the flyoutDirection attribute. The
-- popup contract then runs as Blizzard's: SpellFlyout:Toggle reads the
-- direction, TogglePopup attaches the flyout and ends in OnPopupToggled,
-- the one call of its that lands here.

CamelotGamepadClickMixin = {}

--- The attributes, the clicks and the alpha, from the bar's load. Each
--- attribute write runs Blizzard's UpdateFlyout on this frame.
function CamelotGamepadClickMixin:Arm()
    self:SetAttribute("type", "action")
    self:SetAttribute("typerelease", "actionrelease")
    self:SetAttribute("checkselfcast", true)
    self:SetAttribute("checkfocuscast", true)
    self:SetAttribute("checkmouseovercast", true)
    self:SetAttribute("useOnKeyDown", false)
    -- Blizzard's channel for the popup direction (UpdateFlyout: "needs
    -- securely updating from the value stored in the attribute").
    self:SetAttribute("flyoutDirection", "UP")
    self:RegisterForDrag("LeftButton", "RightButton")
    self:RegisterForClicks("AnyUp", "LeftButtonDown", "RightButtonDown")
    self:SetAlpha(0)
end

-- Replaces FlyoutButtonMixin:OnPopupToggled, TogglePopup's last call after
-- the flyout attaches to or leaves this target: the page unit dims around
-- an open flyout, as Blizzard's does (PageUnit.lua, OnFlyoutOpened), and
-- the popup ignores this target's alpha while it is open.
function CamelotGamepadClickMixin:OnPopupToggled()
    local visual = self.visual
    local bar = visual and visual.parentActionBar
    local unit = bar and bar.pagingUnitOwner
    if not unit then return end
    if self:IsPopupOpen() then
        unit:OnFlyoutOpened(self)
    else
        unit:OnFlyoutClosed()
    end
end

-- The mouse, relayed to the visual: the tooltip and the hover highlight,
-- the pushed look (the pressed geometry is a key's; Blizzard's mouse path
-- skips it too), the pickup, the drop, and the state after a click.
function CamelotGamepadClickMixin:OnEnter()
    local visual = self.visual
    if not visual then return end
    visual:ActionBarButtonMixin_OnEnter()
    visual:LockHighlight()
end

function CamelotGamepadClickMixin:OnLeave()
    local visual = self.visual
    if not visual then return end
    visual:ActionBarButtonMixin_OnLeave()
    visual:UnlockHighlight()
end

function CamelotGamepadClickMixin:OnMouseDown()
    local visual = self.visual
    if visual and visual:GetButtonState() == "NORMAL" then
        visual:SetButtonState("PUSHED")
    end
end

function CamelotGamepadClickMixin:OnMouseUp()
    local visual = self.visual
    if visual and not visual.keyDown and visual:GetButtonState() == "PUSHED" then
        visual:SetButtonState("NORMAL")
    end
end

function CamelotGamepadClickMixin:OnDragStart()
    if self.visual then self.visual:OnDragStart() end
end

function CamelotGamepadClickMixin:OnReceiveDrag()
    if self.visual then self.visual:OnReceiveDrag() end
end

-- As ActionBarActionButtonDerivedMixin_OnPostClick.
function CamelotGamepadClickMixin:PostClick()
    if self.visual then self.visual:UpdateState() end
end

--------------------------------------------------------------------------------
-- The input icons
--------------------------------------------------------------------------------
-- A Camelot stand-in for InputIconTextureFrameTemplate, whose load
-- registers every instance with Blizzard's icon set manager. One texture,
-- the atlas read from the icon set utility at load and again from Refresh
-- when the watcher sees the active set change. The three state setters
-- exist because Blizzard's bar code calls them on a button's prompt;
-- SetTextureState is left out on purpose, so the focus sequences do not
-- take this for an input icon.

CamelotGamepadInputIconMixin = {}

function CamelotGamepadInputIconMixin:OnLoad()
    self:Refresh()
end

--- The atlas for the key again, after an icon set change.
function CamelotGamepadInputIconMixin:Refresh()
    if self.mappedButtonKey then self:SetKey(self.mappedButtonKey) end
end

-- Blizzard's prompt canvas: the newer controller icons are 76 by 75 with
-- their border and shadow padding baked in, and InputIconTextureMixin
-- draws them 5 beyond the frame on every side so they read at the size
-- of the older prompts (InputIconTexture.lua, ApplyTextureLayout). The
-- stand-in does the same, or every prompt comes out a step small.
local PROMPT_CANVAS_WIDTH, PROMPT_CANVAS_HEIGHT = 76, 75
local PROMPT_CANVAS_OVERFLOW = 5

local function isPromptCanvas(atlas)
    local ok, info = pcall(C_Texture.GetAtlasInfo, atlas)
    return ok and type(info) == "table" and info.width == PROMPT_CANVAS_WIDTH
        and info.height == PROMPT_CANVAS_HEIGHT
end

function CamelotGamepadInputIconMixin:SetKey(key)
    self.mappedButtonKey = key
    local ok, atlas = pcall(function()
        return InputIconTextureSetUtility.GetNormalActiveInputIconButtonTexture(key, InputDeviceIconVariant.Standard)
    end)
    local icon = self.Icon
    icon:ClearAllPoints()
    if ok and type(atlas) == "string" then
        icon:SetAtlas(atlas)
        if isPromptCanvas(atlas) then
            icon:SetPoint("TOPLEFT", -PROMPT_CANVAS_OVERFLOW, PROMPT_CANVAS_OVERFLOW)
            icon:SetPoint("BOTTOMRIGHT", PROMPT_CANVAS_OVERFLOW, -PROMPT_CANVAS_OVERFLOW)
        else
            icon:SetAllPoints()
        end
    else
        icon:SetTexture(nil)
        icon:SetAllPoints()
    end
end

function CamelotGamepadInputIconMixin:SetPressable() end
function CamelotGamepadInputIconMixin:SetDisabled() end
function CamelotGamepadInputIconMixin:SetFocused() end

-- Two icons with a plus between them, the LT+RT prompt under the bottom
-- bar. The divider is an icon keyed GAMEPAD_PROMPT_DIVIDER_PLUS, as
-- InputPromptTwoIconTemplate's is, and takes its own key from the XML.
CamelotGamepadInputPairMixin = {}

function CamelotGamepadInputPairMixin:OnLoad()
    self:Refresh()
end

function CamelotGamepadInputPairMixin:Refresh()
    if self.key1 then self.First:SetKey(self.key1) end
    if self.key2 then self.Second:SetKey(self.key2) end
    if self.Divider then self.Divider:Refresh() end
end

--------------------------------------------------------------------------------
-- The page unit
--------------------------------------------------------------------------------
-- Camelot's own frame: nothing of GamepadActionBarPageUnitMixin is applied,
-- since its load registers with InputUtil, the icon set manager and
-- GamepadMode. The watcher in gamepad.lua writes the state the bars read.

CamelotGamepadPageUnitMixin = {}

local ANCHOR_KEYS = { "top", "left", "right", "bottom" }
CamelotGamepadPageUnitMixin.ANCHOR_KEYS = ANCHOR_KEYS

local function anchorFrame(self, key)
    if key == "top" then return self.TopAnchor end
    if key == "left" then return self.LeftAnchor end
    if key == "right" then return self.RightAnchor end
    return self.BottomAnchor
end

function CamelotGamepadPageUnitMixin:OnLoad()
    self.currentPage = 1
    self.activeBar = nil
    self.bars = {}
    self.mirrors = {}
    self.overridden = {}
    for _, key in ipairs(ANCHOR_KEYS) do
        local anchor = anchorFrame(self, key)
        self.bars[key] = anchor.Bar
        self.mirrors[key] = anchor.Mirror
        anchor.Bar:SetPagingUnitOwner(self)
        anchor.Mirror:SetPagingUnitOwner(self)
    end
    -- The three anchors' own points, for the compact fold and back.
    self.anchorPoints = {}
    for _, key in ipairs({ "top", "left", "right" }) do
        local anchor = anchorFrame(self, key)
        local points = {}
        for i = 1, anchor:GetNumPoints() do
            local point, relativeTo, relativePoint, x, y = anchor:GetPoint(i)
            points[#points + 1] = { point = point, relativeTo = relativeTo, relativePoint = relativePoint, x = x, y = y }
        end
        self.anchorPoints[key] = points
    end
end

function CamelotGamepadPageUnitMixin:GetCurrentPage()
    return self.currentPage
end

function CamelotGamepadPageUnitMixin:GetActiveBar()
    return self.activeBar
end

function CamelotGamepadPageUnitMixin:ShouldUseCompactLayout()
    local parent = self:GetParent()
    return parent ~= nil and parent.useCompactLayout == true
end

function CamelotGamepadPageUnitMixin:IsAnchorOverridden(key)
    return self.overridden[key] == true
end

--- Every bar: the action bar and the mirror at each anchor, in anchor order.
function CamelotGamepadPageUnitMixin:EachBar()
    local list = {}
    for _, key in ipairs(ANCHOR_KEYS) do
        list[#list + 1] = self.bars[key]
        list[#list + 1] = self.mirrors[key]
    end
    return ipairs(list)
end

function CamelotGamepadPageUnitMixin:RefreshActionBarVisibilities()
    for _, bar in self:EachBar() do
        bar:RefreshActionBarVisibility()
    end
end

function CamelotGamepadPageUnitMixin:RefreshHighlight()
    for _, bar in self:EachBar() do
        bar:RefreshHighlight()
    end
end

--- The active icon set changed (the watcher's quarter-second tick): every
--- bar's slot art and prompts, and the three modifier icons, again.
function CamelotGamepadPageUnitMixin:RefreshInputIconSet()
    for _, bar in self:EachBar() do
        bar:RefreshInputIconSet()
    end
    for _, key in ipairs({ "LeftIcon", "RightIcon", "CenteredIcons" }) do
        if self[key] then self[key]:Refresh() end
    end
end

--- The page the watcher read off Blizzard's tracker; `force` at the
--- install, so every button writes its first action attribute.
function CamelotGamepadPageUnitMixin:SetPage(page, force)
    if page == self.currentPage and not force then return end
    self.currentPage = page
    for _, key in ipairs(ANCHOR_KEYS) do
        self.bars[key]:SetPage(page)
    end
    self:RefreshActionBarVisibilities()
end

--- The Blizzard override bar shown at an anchor, or nil: the anchor's
--- mirror takes it and the action bar yields the spot.
function CamelotGamepadPageUnitMixin:SetMirrorSource(key, source, name)
    self.overridden[key] = source ~= nil
    self.mirrors[key]:SetSource(source, name)
    self.mirrors[key]:RefreshActionBarVisibility()
    self.bars[key]:RefreshActionBarVisibility()
end

--- The bar Blizzard's page unit has active, as one of this page unit's.
function CamelotGamepadPageUnitMixin:SetActiveBar(bar)
    if bar == self.activeBar then return end
    if self.activeBar then
        self.activeBar:HideHighlight()
        self.activeBar:ClearPushed()
    end
    self.activeBar = bar
    if bar then bar:ShowHighlight() end
    if self:ShouldUseCompactLayout() then
        self:RefreshActionBarVisibilities()
    end
end

-- Blizzard's compact fold (PageUnit.lua, RefreshCompactLayout): the top,
-- left and right anchors over the bottom one, or their own points back.
-- The anchors hold secure buttons, so the move waits out a fight.
function CamelotGamepadPageUnitMixin:SetCompact(compact)
    local function fold()
        for _, key in ipairs({ "top", "left", "right" }) do
            local anchor = anchorFrame(self, key)
            anchor:ClearAllPoints()
            if compact then
                anchor:SetAllPoints(self.BottomAnchor)
            else
                for _, p in ipairs(self.anchorPoints[key]) do
                    anchor:SetPoint(p.point, p.relativeTo, p.relativePoint, p.x, p.y)
                end
            end
        end
        self:RefreshActionBarVisibilities()
    end
    if InCombatLockdown() then
        queue(fold, "camelotActionBars.gamepad.compact")
    else
        fold()
    end
end

-- As GamepadActionBarPageUnitMixin:OnFlyoutOpened and OnFlyoutClosed: a
-- flyout opened by a mouse click on a Camelot button dims everything but
-- the popup. The watcher leaves the alpha alone while one is open.
local FLYOUT_INACTIVE_ALPHA = 0.35

function CamelotGamepadPageUnitMixin:OnFlyoutOpened(button)
    if self.activeFlyoutButton then
        self:OnFlyoutClosed()
    end
    self.activeFlyoutButton = button
    if button.popup then button.popup:SetIgnoreParentAlpha(true) end
    self:SetAlpha(FLYOUT_INACTIVE_ALPHA)
end

function CamelotGamepadPageUnitMixin:OnFlyoutClosed()
    local button = self.activeFlyoutButton
    if button then
        if button.popup then button.popup:SetIgnoreParentAlpha(false) end
        self.activeFlyoutButton = nil
    end
    self:SetAlpha(1)
end
