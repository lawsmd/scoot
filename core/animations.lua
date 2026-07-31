-- animations.lua - Centralized animation registry and factory
local addonName, addon = ...

addon.Animations = addon.Animations or {}
local Anim = addon.Animations

-- Internal registry: [id] = definition
local registry = {}

--------------------------------------------------------------------------------
-- Registration API
--------------------------------------------------------------------------------

function Anim.Register(def)
	if type(def) ~= "table" or type(def.id) ~= "string" then
		error("Animations.Register: definition must be a table with a string 'id'")
	end
	if registry[def.id] then
		error("Animations.Register: duplicate id '" .. def.id .. "'")
	end
	registry[def.id] = def
end

function Anim.GetDefinition(animId)
	return registry[animId]
end

function Anim.GetAllIds()
	local ids = {}
	for id in pairs(registry) do
		ids[#ids + 1] = id
	end
	return ids
end

--------------------------------------------------------------------------------
-- Controller mixin
--------------------------------------------------------------------------------

local ControllerMixin = {}
ControllerMixin.__index = ControllerMixin

function ControllerMixin:Play()
	if self._frame then
		self._frame:Show()
	end
	if self._multiCtrl then
		self._multiCtrl:Play()
	elseif self._animGroup then
		self._animGroup:Play()
	end
end

function ControllerMixin:Stop()
	if self._multiCtrl then
		self._multiCtrl:Stop()
	elseif self._animGroup then
		self._animGroup:Stop()
	end
	if self._frame then
		self._frame:Hide()
	end
end

function ControllerMixin:IsPlaying()
	if self._multiCtrl then
		return self._multiCtrl:IsPlaying()
	end
	if self._animGroup then
		return self._animGroup:IsPlaying()
	end
	return false
end

function ControllerMixin:SetSize(w, h)
	if self._frame then
		self._frame:SetSize(w, h)
	end
	if self._texture then
		self._texture:SetAllPoints(self._frame)
	end
end

function ControllerMixin:SetPoint(...)
	if self._frame then
		self._frame:ClearAllPoints()
		self._frame:SetPoint(...)
	end
end

function ControllerMixin:SetFrameLevel(n)
	if self._frame then
		self._frame:SetFrameLevel(n)
	end
end

function ControllerMixin:SetAlpha(a)
	if self._frame then
		self._frame:SetAlpha(a)
	end
end

function ControllerMixin:Show()
	if self._frame then
		self._frame:Show()
	end
end

function ControllerMixin:Hide()
	if self._frame then
		self._frame:Hide()
	end
end

function ControllerMixin:Destroy()
	if self._multiCtrl and self._multiCtrl.Stop then
		self._multiCtrl:Stop()
	end
	if self._animGroup then
		self._animGroup:Stop()
	end
	if self._frame then
		self._frame:Hide()
		self._frame:SetParent(nil)
	end
	self._frame = nil
	self._texture = nil
	self._animGroup = nil
	self._multiCtrl = nil
end

function ControllerMixin:GetFrame()
	return self._frame
end

function ControllerMixin:GetTexture()
	return self._texture
end

function ControllerMixin:GetAnimGroup()
	return self._animGroup
end

function ControllerMixin:GetTextures()
	if self._multiCtrl and self._multiCtrl._textures then
		return self._multiCtrl._textures
	end
	if self._texture then
		return { self._texture }
	end
	return nil
end

--------------------------------------------------------------------------------
-- Multi-texture controller helper
--------------------------------------------------------------------------------

-- Build the controller that Anim.Create expects back from a `buildController`
-- definition, given a setup callback that populates textures and anim groups.
--
-- setupFn(frame, textures, animGroups) fills both arrays; animGroups[1] is
-- treated as the lead group, so it is the one that decides when the effect is
-- over. Stop() zeroes every texture's alpha as well as halting the groups: a
-- group stopped mid-flight leaves its target wherever the interpolation had
-- reached, which for an additive effect is a bright smear that never clears.
function Anim.BuildMultiTextureController(frame, setupFn)
	local textures = {}
	local animGroups = {}

	setupFn(frame, textures, animGroups)

	if animGroups[1] then
		animGroups[1]:SetScript("OnFinished", function()
			frame:Hide()
		end)
	end

	return {
		_textures = textures,
		Play = function(self)
			for _, ag in ipairs(animGroups) do ag:Play() end
		end,
		Stop = function(self)
			for _, ag in ipairs(animGroups) do ag:Stop() end
			for _, tex in ipairs(textures) do tex:SetAlpha(0) end
		end,
		IsPlaying = function(self)
			return animGroups[1] and animGroups[1]:IsPlaying() or false
		end,
	}
end

--------------------------------------------------------------------------------
-- Factory
--------------------------------------------------------------------------------

function Anim.Create(animId, parent, existingTexture)
	local def = registry[animId]
	if not def then
		error("Animations.Create: unknown animation id '" .. tostring(animId) .. "'")
	end
	if not parent then
		error("Animations.Create: parent is required")
	end

	local ctrl = setmetatable({}, ControllerMixin)

	-- Frame (owns the texture and animation)
	local frame = CreateFrame("Frame", nil, parent)
	frame:Hide()
	ctrl._frame = frame

	-- Apply default size if provided
	if def.defaultSize then
		frame:SetSize(def.defaultSize[1], def.defaultSize[2])
	end

	-- Texture: use existing or create from definition
	local tex = existingTexture
	if not tex and def.texture then
		tex = frame:CreateTexture(nil, "OVERLAY")
		tex:SetTexture(def.texture)
		tex:SetAllPoints(frame)
	elseif not tex and not def.texture and def.buildAnimGroup then
		-- buildAnimGroup needs a texture even if the definition doesn't specify one
		-- (the callback will set the texture/atlas itself)
		tex = frame:CreateTexture(nil, "OVERLAY")
		tex:SetAllPoints(frame)
	end
	ctrl._texture = tex

	-- Build animation group via the definition's callback
	if def.buildController then
		-- Multi-texture path: buildController creates its own textures + animGroups
		local multiCtrl = def.buildController(frame)
		ctrl._multiCtrl = multiCtrl

		-- Alert category: the controller's first animGroup should wire OnFinished
		-- to hide the frame. We also set up a fallback here.
		if def.category == "alert" and multiCtrl then
			local origPlay = multiCtrl.Play
			multiCtrl.Play = function(self)
				frame:Show()
				origPlay(self)
			end
		end
	elseif def.buildAnimGroup and tex then
		local ag = def.buildAnimGroup(tex)
		ctrl._animGroup = ag

		-- Alert category: auto-hide on finish
		if def.category == "alert" and ag then
			ag:SetScript("OnFinished", function()
				frame:Hide()
			end)
		end
	end

	return ctrl
end

--------------------------------------------------------------------------------
-- Built-in animation registrations
--------------------------------------------------------------------------------

-- 1. exclamationBlink: looping alpha bounce on the Exclamation.tga texture
Anim.Register({
	id = "exclamationBlink",
	category = "loop",
	texture = "Interface\\AddOns\\Scoot\\media\\animations\\Exclamation",
	defaultSize = { 16, 16 },
	buildAnimGroup = function(tex)
		local ag = tex:CreateAnimationGroup()
		ag:SetLooping("BOUNCE")
		local fade = ag:CreateAnimation("Alpha")
		fade:SetFromAlpha(1.0)
		fade:SetToAlpha(0.0)
		fade:SetDuration(0.5)
		return ag
	end,
})

-- 2. oneUp: alert FlipBook sprite sheet + upward Translation using 1UP.tga
Anim.Register({
	id = "oneUp",
	category = "alert",
	texture = "Interface\\AddOns\\Scoot\\media\\animations\\1UP",
	defaultSize = { 64, 64 },
	buildAnimGroup = function(tex)
		local ag = tex:CreateAnimationGroup()
		ag:SetLooping("NONE")

		-- FlipBook sprite sheet (params may need in-game verification)
		local fb = ag:CreateAnimation("FlipBook")
		fb:SetFlipBookRows(1)
		fb:SetFlipBookColumns(4)
		fb:SetFlipBookFrames(4)
		fb:SetDuration(1.5)

		-- Upward translation over the same duration
		local move = ag:CreateAnimation("Translation")
		move:SetOffset(0, 40)
		move:SetDuration(1.5)
		move:SetSmoothing("OUT")

		-- Fade out toward the end
		local fade = ag:CreateAnimation("Alpha")
		fade:SetFromAlpha(1.0)
		fade:SetToAlpha(0.0)
		fade:SetStartDelay(0.8)
		fade:SetDuration(0.7)

		return ag
	end,
})

-- 3. alphaPulse: code-only looping alpha bounce (caller passes existingTexture)
Anim.Register({
	id = "alphaPulse",
	category = "loop",
	texture = nil,
	buildAnimGroup = function(tex)
		local ag = tex:CreateAnimationGroup()
		ag:SetLooping("BOUNCE")
		local fade = ag:CreateAnimation("Alpha")
		fade:SetFromAlpha(1.0)
		fade:SetToAlpha(0.3)
		fade:SetDuration(0.5)
		return ag
	end,
})
