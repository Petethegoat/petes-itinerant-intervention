local configPath = "Pete's Itinerant Intervention"
local i18n = mwse.loadTranslations(configPath)

local defaultConfig = {
	ghostfenceInterventionGoesToGhostgate = true,
	ghostgatePullBackupCell = i18n("defaultGhostgateCell"),
	almsiviInterventionFailsInGhostfence = false,
	divineInterventionFailsInGhostfence = true,
	recallExitFailsInGhostfence = true,
	recallEnterFailsInGhostfence = true,
	useInteriorInterventionWhenAvailable = true,
	showInterventionDestinationOnTooltip = true,
	showMarkRecallDestinationOnTooltip = true,
	enableGhostfenceEdits = false,
    ---@type mwseKeyMouseCombo
	editorPlacementHotkey = { keyCode = tes3.scanCode.g },
    ---@type mwseKeyMouseCombo
	editorTestHotkey = { keyCode = tes3.scanCode.c },
}
local config = mwse.loadConfig(configPath, defaultConfig)

local ghostfencePath = "ghostfence_polygon"
local ghostfencePolygon

local teleportDisabledMsg
local spellResistGMST

local allInterventionMarkers = {}

--- @param e initializedEventData
local function initializedCallback(e)
	spellResistGMST = tes3.findGMST(tes3.gmst.sMagicPCResisted)
	teleportDisabledMsg = tes3.findGMST(tes3.gmst.sTeleportDisabled).value
	local doorMarker = tes3.getReference(i18n("doorMarker")).object
	local travelMarker = tes3.getReference(i18n("travelMarker")).object

	for _, cell in pairs(tes3.dataHandler.nonDynamicData.cells) do
		for static in cell:iterateReferences(tes3.objectType.static) do
			if static.object.isLocationMarker and static.object ~= doorMarker and static.object ~= travelMarker then
				local position = cell.isInterior and 1 or #allInterventionMarkers + 1
				table.insert(allInterventionMarkers, position, static)
				break
			end
		end
	end
end
event.register(tes3.event.initialized, initializedCallback)

--- @param point tes3vector3
local function isInsideGhostfence(point)
	if not ghostfencePolygon then return true end

	--thx peter gilmour of stackexchange 
	local oddNodes = false
	local j = #ghostfencePolygon
	for i = 1, #ghostfencePolygon do
		if ghostfencePolygon[i].y < point.y and ghostfencePolygon[j].y >= point.y or ghostfencePolygon[j].y < point.y and ghostfencePolygon[i].y >= point.y then
			if ghostfencePolygon[i].x + ( point.y - ghostfencePolygon[i].y ) / (ghostfencePolygon[j].y - ghostfencePolygon[i].y) * (ghostfencePolygon[j].x - ghostfencePolygon[i].x) < point.x then
				oddNodes = not oddNodes;
			end
		end
		j = i;
	end

	return oddNodes
end

--- @return boolean
local function playerBlockedByGhostfence()
	if tes3.findGlobal(i18n("blightGlobal")).value == 1 or tes3.findGlobal(i18n("heartGlobal")).value == 1 then return false end
	return isInsideGhostfence(tes3.getClosestExteriorPosition())
end

--- @param cell tes3cell
--- @return tes3reference
-- Thanks hrnchamd, again
local function cocReference(cell)
    local doorMarker = tes3.getObject(i18n("doorMarker"))
    -- Find first door marker from persistent refs.
    for r in cell:iterateReferences(tes3.objectType.static) do
        if r.object == doorMarker then return r end
    end
    -- Fallback, use first available persistent ref.
    return cell.activators[1]
end

--- @param position tes3vector3
--- @param type tes3.effect
--- @return tes3reference
local function nearestInterventionMarker(position, type)
	local nearestMarker
	local nearestInteriorMarker
	local nearestExteriorMarker
	local minimumDist = math.huge
	local minimumDistInt = math.huge
	local minimumDistExt = math.huge
	local ghostgateRef

	if config.ghostfenceInterventionGoesToGhostgate and type == tes3.effect.almsiviIntervention and playerBlockedByGhostfence() then
		ghostgateRef = cocReference(tes3.getCell{ id = config.ghostgatePullBackupCell })
		position = tes3.getClosestExteriorPosition{ reference = ghostgateRef }
	end

	for _, i in pairs(allInterventionMarkers) do
		if (type == tes3.effect.almsiviIntervention and i.id == i18n("templeMarker"))
		or (type == tes3.effect.divineIntervention and i.id == i18n("divineMarker")) then
			local target = tes3.getClosestExteriorPosition{ reference = i }
			if target ~= nil then
				local dist = position:distance(target)
				if dist < minimumDist then
					nearestMarker = i
					minimumDist = dist
				end
				if i.cell.isInterior and dist < minimumDistInt then
					nearestInteriorMarker = i
					minimumDistInt = dist
				elseif not i.cell.isInterior and dist < minimumDistExt then
					nearestExteriorMarker = i
					minimumDistExt = dist
				end
			end
		end
	end

	if config.ghostfenceInterventionGoesToGhostgate and type == tes3.effect.almsiviIntervention and playerBlockedByGhostfence() then
		-- If there's no marker added for ghostgate, we use our backup cell. Compare distance to decide if there's a ghostgate marker or not.
		if nearestMarker.position:distance(tes3.getClosestExteriorPosition{ reference = ghostgateRef }) > 10000 then
			nearestMarker = ghostgateRef
		end
	end
	
	local nearPos = tes3.getClosestExteriorPosition{ reference = nearestMarker }
	if config.useInteriorInterventionWhenAvailable then -- Prefer interiors.
		if nearPos:distance(tes3.getClosestExteriorPosition{ reference = nearestInteriorMarker }) > 3000 then
			return nearestMarker
		else
			return nearestInteriorMarker
		end
	else -- Then prefer exteriors instead.
		if nearPos:distance(nearestExteriorMarker.position) > 3000 then
			return nearestMarker
		else
			return nearestExteriorMarker
		end
	end
end

--- @param e spellResistEventData
local function preventSpell(e)
	local prevText = spellResistGMST.value
	spellResistGMST.value = teleportDisabledMsg
	e.resistedPercent = 100
	timer.delayOneFrame(function()
		spellResistGMST.value = prevText
	end)
end

--- @param e spellResistEventData
--- @param target tes3reference
local function redirectTeleport(e, target)
	local prevText = spellResistGMST.value
	spellResistGMST.value = ""
	e.resistedPercent = 100
	timer.delayOneFrame(function()
		tes3.positionCell{ reference = tes3.mobilePlayer, cell = target.cell, position = target.position}
		spellResistGMST.value = prevText
	end)
end

--- @param e spellResistEventData
local function spellResistCallback(e)
	if e.caster ~= tes3.player then return end
	if e.effect.id ~= tes3.effect.almsiviIntervention
	and e.effect.id ~= tes3.effect.divineIntervention
	and e.effect.id ~= tes3.effect.recall then return end

	if config.recallEnterFailsInGhostfence and e.effect.id == tes3.effect.recall then
		local markPos
		if tes3.mobilePlayer.markLocation.cell.isInterior then
			markPos = tes3.getClosestExteriorPosition{ reference = cocReference(tes3.mobilePlayer.markLocation.cell) }
		else
			markPos = tes3.mobilePlayer.markLocation.position
		end

		if isInsideGhostfence(markPos) then
			preventSpell(e)
			tes3.playSound{ sound = i18n("soundFail"), mixChannel = tes3.soundMix.effects }
		end
	end

	if ((config.almsiviInterventionFailsInGhostfence and e.effect.id == tes3.effect.almsiviIntervention)
	or (config.divineInterventionFailsInGhostfence and e.effect.id == tes3.effect.divineIntervention)
	or (config.recallExitFailsInGhostfence and e.effect.id == tes3.effect.recall))
	and playerBlockedByGhostfence() then
		preventSpell(e)
		tes3.playSound{ sound = i18n("soundFail"), mixChannel = tes3.soundMix.effects }
	elseif e.effect.id == tes3.effect.almsiviIntervention
	or e.effect.id == tes3.effect.divineIntervention then
		-- Also use our own teleport logic to allow interior cells.
		redirectTeleport(e, nearestInterventionMarker(tes3.getClosestExteriorPosition(), e.effect.id))
		tes3.playSound{ sound = i18n("soundSuccess"), mixChannel = tes3.soundMix.effects }
	end
end
event.register(tes3.event.spellResist, spellResistCallback)

--- @param e keyDownEventData
local function keyDownCallback(e)
	if tes3.onMainMenu() or tes3.menuMode() then return end
	if not config.enableGhostfenceEdits then return end
	if e.keyCode == config.editorPlacementHotkey.keyCode then
		table.insert(ghostfencePolygon, { x = tes3.mobilePlayer.position.x, y = tes3.mobilePlayer.position.y })
		mwse.saveConfig(ghostfencePath, ghostfencePolygon)
		tes3.messageBox("#" .. #ghostfencePolygon .. i18n("pointSaved") .. math.round(tes3.mobilePlayer.position.x) .. ", " .. math.round(tes3.mobilePlayer.position.y))
	elseif e.keyCode == config.editorTestHotkey.keyCode then
		tes3.messageBox(isInsideGhostfence(tes3.getClosestExteriorPosition()) and i18n("insideGhostfence") or i18n("outsideGhostfence"))
	end
end
event.register(tes3.event.keyDown, keyDownCallback)

--- @param effects tes3effect[]
--- @param tooltip tes3uiElement
--- @return tes3uiElement --nil if we didn't add to the tooltip
local function iterateEffectsForTooltip(effects, tooltip)
	local added = nil
	for _, effect in ipairs(effects) do
		if effect.id == tes3.effect.almsiviIntervention
		or effect.id == tes3.effect.divineIntervention then
			if config.showInterventionDestinationOnTooltip then
				added = tooltip:getContentElement():createLabel{
					text = i18n("destination") .. nearestInterventionMarker(tes3.getClosestExteriorPosition(), effect.id).cell.name
				}
			end
		elseif effect.id == tes3.effect.recall or effect.id == tes3.effect.mark then
			if config.showMarkRecallDestinationOnTooltip and tes3.mobilePlayer.markLocation ~= nil then
				local destText = tes3.mobilePlayer.markLocation.cell.name ~= nil and tes3.mobilePlayer.markLocation.cell.name or tes3.mobilePlayer.markLocation.cell.region.name
				added = tooltip:getContentElement():createLabel{
					text = i18n("destination") .. destText
				}
			end
		end
	end
	return added
end

--- @param e uiSpellTooltipEventData
local function uiSpellTooltipCallback(e)
	if not config.showInterventionDestinationOnTooltip and not config.showMarkRecallDestinationOnTooltip then return end
	local added = iterateEffectsForTooltip(e.spell.effects, e.tooltip)
	if added ~= nil then
		local divide = e.tooltip:createDivider()
		divide.widthProportional = 0.85
		divide.parent:reorderChildren(added, divide, 1)
	end
end
event.register(tes3.event.uiSpellTooltip, uiSpellTooltipCallback, { priority = 0 })

--- @param e uiObjectTooltipEventData
local function uiObjectTooltipCallback(e)
	if not config.showInterventionDestinationOnTooltip and not config.showMarkRecallDestinationOnTooltip then return end
	if e.object.enchantment == nil then return end
	iterateEffectsForTooltip(e.object.enchantment.effects, e.tooltip)
end
event.register(tes3.event.uiObjectTooltip, uiObjectTooltipCallback, { priority = 0 })

local function registerModConfig()
    local template = mwse.mcm.createTemplate{
        name = configPath,
        config = config
    }

    template:register()
    template:saveOnClose(configPath, config)
    local page = template:createPage()

    page:createInfo{
        label = configPath,
        text = i18n("description")
    }

	local general = page:createCategory{
		label = i18n("generalTitle"),
		childIndent = 20
	}
    general:createYesNoButton{
        label = i18n("useInteriorInterventionWhenAvailable"),
        configKey = "useInteriorInterventionWhenAvailable" }
    general:createYesNoButton{
        label = i18n("showInterventionDestinationOnTooltip"),
        configKey = "showInterventionDestinationOnTooltip" }
	general:createYesNoButton{
		label = i18n("showMarkRecallDestinationOnTooltip"),
		configKey = "showMarkRecallDestinationOnTooltip" }

	local other = page:createCategory{
		label = i18n("divineAndMarkTitle"),
		childIndent = 20
	}
    other:createYesNoButton{
        label = i18n("divineInterventionFailsInGhostfence"),
        configKey = "divineInterventionFailsInGhostfence" }
	other:createYesNoButton{
		label = i18n("recallExitFailsInGhostfence"),
		configKey = "recallExitFailsInGhostfence" }
	other:createYesNoButton{
		label = i18n("recallEnterFailsInGhostfence"),
		configKey = "recallEnterFailsInGhostfence" }

	local almsivi = page:createCategory{
		label = i18n("almsiviTitle"),
		childIndent = 20
	}
    almsivi:createYesNoButton{
        label = i18n("almsiviInterventionFailsInGhostfence"),
        configKey = "almsiviInterventionFailsInGhostfence" }
	almsivi:createYesNoButton{
        label = i18n("ghostfenceInterventionGoesToGhostgate"),
        configKey = "ghostfenceInterventionGoesToGhostgate" }
	almsivi:createTextField{
        label = i18n("ghostgatePullBackupCell"),
        configKey = "ghostgatePullBackupCell" }

	local editor = page:createCategory{
		label = i18n("editorTitle"),
		childIndent = 20
	}
	editor:createYesNoButton{
        label = i18n("enableGhostfenceEdits"),
        configKey = "enableGhostfenceEdits" }
	editor:createKeyBinder{
		label = i18n("editorPlacementHotkey"),
		configKey = "editorPlacementHotkey",
		allowCombinations = false }
	editor:createKeyBinder{
		label = i18n("editorTestHotkey"),
		configKey = "editorTestHotkey",
		allowCombinations = false }
	editor:createButton{
        label = i18n("clearGhostfenceFile"),
		buttonText = i18n("clear"),
		callback = function()
			mwse.saveConfig(ghostfencePath, {})
			tes3.messageBox(i18n("clearedMessage"))
		end }
	editor:createInfo{
        text = i18n("restoreGhostfenceVanilla") }
end
event.register(tes3.event.modConfigReady, registerModConfig)

--Vanilla Ghostfence boundary. Load it this way so installing the mod can't overwrite a customised one.
ghostfencePolygon = mwse.loadConfig(ghostfencePath, {
	{ y = 39871, x = 22911 },
	{ y = 39865, x = 18819 },
	{ y = 39871, x = 15732 },
	{ y = 39891, x = 11655 },
	{ y = 39961, x = 8524 },
	{ y = 42520, x = 6634 },
	{ y = 45589, x = 6245 },
	{ y = 48658, x = 6970 },
	{ y = 51541, x = 7712 },
	{ y = 54164, x = 8242 },
	{ y = 58256, x = 8212 },
	{ y = 61132, x = 7304 },
	{ y = 64171, x = 6756 },
	{ y = 66475, x = 4667 },
	{ y = 68404, x = 2356 },
	{ y = 69696, x = -292 },
	{ y = 70276, x = -3170 },
	{ y = 72208, x = -5587 },
	{ y = 74296, x = -7913 },
	{ y = 76063, x = -10414 },
	{ y = 77676, x = -14202 },
	{ y = 79098, x = -17932 },
	{ y = 83069, x = -18713 },
	{ y = 86156, x = -18456 },
	{ y = 90270, x = -17871 },
	{ y = 91875, x = -15179 },
	{ y = 93259, x = -12329 },
	{ y = 95530, x = -10267 },
	{ y = 97622, x = -7979 },
	{ y = 98212, x = -4956 },
	{ y = 98347, x = -1894 },
	{ y = 99226, x = 1044 },
	{ y = 100118, x = 3855 },
	{ y = 98973, x = 6687 },
	{ y = 98144, x = 9602 },
	{ y = 97440, x = 12558 },
	{ y = 97414, x = 15547 },
	{ y = 98078, x = 18479 },
	{ y = 98523, x = 21580 },
	{ y = 98485, x = 25613 },
	{ y = 98467, x = 29747 },
	{ y = 97854, x = 32722 },
	{ y = 97916, x = 35551 },
	{ y = 97227, x = 38532 },
	{ y = 96227, x = 41379 },
	{ y = 94377, x = 43806 },
	{ y = 91643, x = 45470 },
	{ y = 88818, x = 46731 },
	{ y = 85836, x = 47415 },
	{ y = 82817, x = 47241 },
	{ y = 78750, x = 47055 },
	{ y = 75656, x = 46959 },
	{ y = 72516, x = 46561 },
	{ y = 69890, x = 44967 },
	{ y = 66977, x = 43917 },
	{ y = 64203, x = 42836 },
	{ y = 61301, x = 41889 },
	{ y = 58651, x = 40348 },
	{ y = 56286, x = 38627 },
	{ y = 53474, x = 37631 },
	{ y = 50624, x = 36519 },
	{ y = 47701, x = 35267 },
	{ y = 43751, x = 33932 },
	{ y = 41527, x = 31690 },
	{ y = 39851, x = 29057 },
	{ y = 39924, x = 25968 },
	{ y = 39883, x = 22896 },
})
--Nice to have a file written to disk.
mwse.saveConfig(ghostfencePath, ghostfencePolygon)