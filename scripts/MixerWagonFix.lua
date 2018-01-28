-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ --
-- MixerWagon Fix script
--
-- Purpose: This script adds mixing time and decay of mixed rations to all mixerwagons.
-- 
-- Authors: Timmiej93
--
-- Copyright (c) Timmiej93, 2017
-- For more information on copyright for this mod, please check the readme file on Github
--
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ --

MixerWagonFix = {}
local SETTLE_INTERVAL = 15

function MixerWagonFix.prerequisitesPresent(specializations)
    return true
end

local MixerWagonFixLoaded = false
function MixerWagonFix:load(savegame)
    self.update = Utils.appendedFunction(self.update, MixerWagonFix.updateAppend)
    self.draw = Utils.appendedFunction(self.draw, MixerWagonFix.drawAppend)
    self.readUpdateStream = Utils.appendedFunction(self.readUpdateStream, MixerWagonFix.T93_readUpdateStream)
    self.writeUpdateStream = Utils.appendedFunction(self.writeUpdateStream, MixerWagonFix.T93_writeUpdateStream)

    self.drawMixerWagonFixAppend = MixerWagonFix.drawMixerWagonFixAppend
    self.addMixingTime = MixerWagonFix.addMixingTime
    self.resetMixingTime = MixerWagonFix.resetMixingTime
    self.doDecay = MixerWagonFix.doDecay
    self.minuteChanged = MixerWagonFix.minuteChanged
    self.calculatePercentage = MixerWagonFix.calculatePercentage

    -- 1, 2, 3, easy, normal, hard
    local difficulty = g_currentMission.missionInfo.difficulty
    local mixingTimes = {[1]=15, [2]=30, [3]=60}
    local settleTimes = {[1]=36, [2]=24, [3]=12}
    self.requiredMixingTime = mixingTimes[difficulty] -- In seconds
    self.fullSettleTime = settleTimes[difficulty] -- In hours
    self.startSettleTime = self.fullSettleTime / 6
    self.decreasePerInterval = (self.requiredMixingTime*1000) / (self.fullSettleTime / (SETTLE_INTERVAL/60))

    self.currentMixingTime = 0
    self.currentSettleTime = 0
    self.mixingTimePercentage = 0

    local uiScale = g_gameSettings:getValue("uiScale")
    local width, height = getNormalizedScreenValues(208*uiScale, 8*uiScale)
    self.statusBar = {}
    self.statusBar.statusBarColor = {0.2122, 0.5271, 0.0307, 1}
    self.statusBar.statusBarColor2 = {0.2832, 0.0091, 0.0091, 1}
    self.statusBar.bar = StatusBar:new(g_baseUIFilename, g_colorBgUVs, nil, {0.0075, 0.0075, 0.0075, 1}, self.statusBar.statusBarColor2, nil, 0, 0, (width*0.85), height)

	g_currentMission.environment:addMinuteChangeListener(self)

	self.lastCalledHour = 0
	self.lastCalledMinute = 0

    self.lastFillInfo = {}
    MixerWagonFixLoaded = true
end

function MixerWagonFix:postLoad(savegame)
    if savegame ~= nil and not savegame.resetVehicles then
        local currentMixingTime = getXMLInt(savegame.xmlFile, savegame.key.."#currentMixingTime")
        local currentSettleTime = getXMLInt(savegame.xmlFile, savegame.key.."#currentSettleTime")
        if (currentMixingTime ~= nil) then
            self.currentMixingTime = currentMixingTime
        end
        if (currentSettleTime ~= nil) then
        	self.currentSettleTime = currentSettleTime
        end
        self:calculatePercentage()
    end
end

function MixerWagonFix:getSaveAttributesAndNodes(nodeIdent)
    local attributes, nodes = "", ""
    attributes = "currentMixingTime=\""..tostring(self.currentMixingTime).."\""
    attributes = attributes .. " currentSettleTime=\""..tostring(self.currentSettleTime).."\""
    return attributes, nodes
end

function MixerWagonFix:readStream(streamId, connection)
    local currentMixingTime = streamReadUInt16(streamId)
    self.currentMixingTime = (currentMixingTime*3)
end

function MixerWagonFix:writeStream(streamId, connection)
   streamWriteUInt16(streamId, (self.currentMixingTime/3))
end

function MixerWagonFix:T93_readUpdateStream(streamId, timestamp, connection)
    if (connection:getIsServer()) then
        currentMixingTime = streamReadUInt16(streamId)
        self.currentMixingTime = (currentMixingTime*3)
    end
end

function MixerWagonFix:T93_writeUpdateStream(streamId, connection, dirtyMask)
    if (not connection:getIsServer()) then
        streamWriteUInt16(streamId, (self.currentMixingTime/3))
    end
end

function MixerWagonFix:update(dt)end
function MixerWagonFix:draw()end
function MixerWagonFix:delete()end
function MixerWagonFix:mouseEvent(posX, posY, isDown, isUp, button)end
function MixerWagonFix:keyEvent(unicode, sym, modifier, isDown)end

function MixerWagonFix:minuteChanged()
	local minute = g_currentMission.environment.currentMinute
	local hour = g_currentMission.environment.currentHour

	if (minute % SETTLE_INTERVAL == 0 and MixerWagonFixLoaded and self:getFillLevel() > 0 and self.currentMixingTime > 0 and self.currentSettleTime < self.fullSettleTime and not self:getIsTurnedOn()) then
		local todo = (self.lastCalledHour ~= hour or self.lastCalledMinute ~= minute)

		if (todo) then
			self.lastCalledHour = hour
			self.lastCalledMinute = minute

			self:doDecay()
		end
	end
end

function MixerWagonFix:doDecay()
	self.currentSettleTime = math.min(self.currentSettleTime + (SETTLE_INTERVAL / 60), self.startSettleTime) -- Convert minutes to hours
	if (self.currentSettleTime >= self.startSettleTime) then	-- If over 2/4/6 hours, start settling
		self:addMixingTime(-self.decreasePerInterval)
	end
	MixerWagonFix_DecayEvent.sendEvent(self, self.currentMixingTime, self.currentSettleTime)
end

function MixerWagonFix:updateAppend(dt)
    if MixerWagonFixLoaded and self:getFillLevel() > 0 and (self.mixingActiveTimer > 0 or self:getIsTurnedOn() or self.tipState == Trailer.TIPSTATE_OPENING or self.tipState == Trailer.TIPSTATE_OPEN) then
        self:addMixingTime(dt)
    end
end

function MixerWagonFix:addMixingTime(dt)
    local maxClamp = 0
    if (not self.isSingleFilled) then
        maxClamp = (self.requiredMixingTime*1000)/3
        if (self.currentMixingTime > maxClamp) then
            maxClamp = self.currentMixingTime
        end
    end
    if (self.forageOk) then
        maxClamp = (self.requiredMixingTime*1000)
    end
    
    self.currentMixingTime = Utils.clamp((self.currentMixingTime + dt), 0, maxClamp)
    self:calculatePercentage()

    local fillLevel = self:getUnitFillLevel(self.mixerWagon.fillUnitIndex)
    if (self.mixingTimePercentage >= 1) then
        if (self.forageOk) then
            self:setUnitFillLevel(self.mixerWagon.fillUnitIndex, fillLevel, FillUtil.FILLTYPE_FORAGE, true, nil, true)
        end
    elseif (not self.isSingleFilled) then
        self:setUnitFillLevel(self.mixerWagon.fillUnitIndex, fillLevel, FillUtil.FILLTYPE_FORAGE_MIXING, true, nil, true)
    end

    if (self.currentSettleTime > 0) then
    	self.currentSettleTime = self.currentSettleTime - ((dt/1000)) -- Remove an hour of settletime per second of mixing time
    end
end

function MixerWagonFix:calculatePercentage()
    self.mixingTimePercentage = self.currentMixingTime/(self.requiredMixingTime*1000)
end

function MixerWagonFix:resetMixingTime()
    self.currentMixingTime = 0
end

function MixerWagonFix:drawAppend()
    if g_currentMission.inGameMessage:getIsVisible() then return end

    if self:getIsActiveForInput(true) then
        local helpHeight = self.mixerWagonHelpHeightPerFruit + self.mixerWagonHelpHeightOffset
        g_currentMission:addHelpTextFunction(self.drawMixerWagonFixAppend, self, helpHeight, nil)
    end
end

function MixerWagonFix:drawMixerWagonFixAppend(posY, param)
    local posX = g_currentMission.helpBoxTextPos1X
    local posX2 = g_currentMission.helpBoxTextPos2X

    setTextColor(g_currentMission.helpBoxTextColor[1], g_currentMission.helpBoxTextColor[2], g_currentMission.helpBoxTextColor[3], g_currentMission.helpBoxTextColor[4])

    posY = posY - self.mixerWagonHelpHeightPerFruit
    setTextBold(true)
    renderText(posX, posY + (self.mixerWagonHelpHeightPerFruit-g_currentMission.helpBoxTextSize)*0.5, g_currentMission.helpBoxTextSize, g_i18n:getText("T93_MIXING_TIME"))
    setTextBold(false)
    renderText(posX2-((self.statusBar.bar.width/0.85)*0.1), posY + (self.mixerWagonHelpHeightPerFruit-g_currentMission.helpBoxTextSize)*0.5, g_currentMission.helpBoxTextSize, string.format(g_i18n:getText("T93_SECONDS_SUFFIX"), Utils.clamp(math.ceil(self.requiredMixingTime-(self.currentMixingTime/1000)), 0, self.requiredMixingTime)))

    if self.mixingTimePercentage < 1 then
        self.statusBar.bar:setColor(unpack(self.statusBar.statusBarColor2))
    else
        self.statusBar.bar:setColor(unpack(self.statusBar.statusBarColor))
    end

    self.statusBar.bar:setPosition(posX2 - (self.statusBar.bar.width/0.85), posY+(self.mixerWagonHelpHeightPerFruit-self.statusBar.bar.height)*0.5)
    self.statusBar.bar:setValue(self.mixingTimePercentage)
    self.statusBar.bar:render()
end

function MixerWagon.setUnitFillLevel(self, superFunc, fillUnitIndex, fillLevel, fillType, force, fillInfo, manualSuperFunc)
    local function superFuncExtra(self, fillUnitIndex, fillLevel, fillType, force, fillInfo)
        self.lastFillInfo = {}
        self.lastFillInfo.self = self
        self.lastFillInfo.fillUnitIndex = fillUnitIndex
        self.lastFillInfo.fillLevel = fillLevel
        self.lastFillInfo.fillType = fillType
        self.lastFillInfo.force = force
        self.lastFillInfo.fillInfo = fillInfo

        superFunc(self, fillUnitIndex, fillLevel, fillType, force, fillInfo)
    end
    if manualSuperFunc then
        superFuncExtra(self, fillUnitIndex, fillLevel, fillType, force, fillInfo)
        return
    end

    if fillUnitIndex ~= self.mixerWagon.fillUnitIndex then
        superFuncExtra(self, fillUnitIndex, fillLevel, fillType, force, fillInfo)
        return
    end

    if not self:allowFillType(fillType, false) then
        return
    end

    fillLevel = Utils.clamp(fillLevel, 0, self:getUnitCapacity(self.mixerWagon.fillUnitIndex))

    local mixerWagonFillType = self.fillTypeToMixerWagonFillType[fillType]
    if mixerWagonFillType == nil then
        if fillLevel == 0 and fillType == FillUtil.FILLTYPE_UNKNOWN then
            for _,entry in pairs(self.mixerWagonFillTypes) do
                entry.fillLevel = 0
            end
            superFuncExtra(self, fillUnitIndex, fillLevel, fillType, true, fillInfo)
            return
        end

        -- used for discharge
        if fillLevel < self:getUnitFillLevel(self.mixerWagon.fillUnitIndex) and self:getUnitFillLevel(self.mixerWagon.fillUnitIndex) > 0 then
            -- remove values from all fill types such that the ratio doesn't change
            fillLevel = Utils.clamp(fillLevel, 0, self:getUnitCapacity(self.mixerWagon.fillUnitIndex))
            local delta = fillLevel - self:getUnitFillLevel(self.mixerWagon.fillUnitIndex)

            local newFillLevel = 0
            for _, entry in pairs(self.mixerWagonFillTypes) do
                local entryDelta = delta * (entry.fillLevel / self:getUnitFillLevel(self.mixerWagon.fillUnitIndex))
                entry.fillLevel = math.max(entry.fillLevel + entryDelta, 0)
                newFillLevel = newFillLevel + entry.fillLevel
            end

            if newFillLevel <= 0 and MixerWagonFixLoaded then
                self:resetMixingTime()
            end

            self:raiseDirtyFlags(self.mixerWagonDirtyFlag)

            superFuncExtra(self, fillUnitIndex, newFillLevel, fillType, force, fillInfo)
        end
        return
    end

    local fillUnitIndex = self.mixerWagon.fillUnitIndex
    local fillUnit = self.fillUnits[fillUnitIndex]

    local delta = fillLevel - fillUnit.fillLevel
    local free = fillUnit.capacity - fillUnit.fillLevel

    if delta > 0 then
        mixerWagonFillType.fillLevel = mixerWagonFillType.fillLevel + math.min(free, delta)
    elseif delta < 0 then
        mixerWagonFillType.fillLevel = math.max(0, mixerWagonFillType.fillLevel + delta)
    end

    if delta > 0 then
        -- self.mixingActiveTimer = self.mixingActiveTimerMax
        self.mixerWagonLastPickupTime = g_currentMission.time

        if MixerWagonFixLoaded then
            local decreasedMixingAmplifier = (self:getUnitFillLevel(fillUnitIndex)/self:getUnitCapacity(fillUnitIndex))*4
            local decreasedMixing = ((delta/self:getUnitCapacity(fillUnitIndex))*(self.requiredMixingTime*1000))*decreasedMixingAmplifier
            self:addMixingTime(-decreasedMixing)
        end
    end

    local newFillLevel = 0
    for _, mixerWagonFillType in pairs(self.mixerWagonFillTypes) do
        newFillLevel = newFillLevel + mixerWagonFillType.fillLevel
    end
    newFillLevel = Utils.clamp(newFillLevel, 0, self:getUnitCapacity(fillUnitIndex))

    local newFillType = FillUtil.FILLTYPE_UNKNOWN

    local isSingleFilled = false
    for _, mixerWagonFillType in pairs(self.mixerWagonFillTypes) do
        if newFillLevel == mixerWagonFillType.fillLevel then
            isSingleFilled = true
            newFillType = next(mixerWagonFillType.fillTypes)
            break
        end
    end

    local isForageOk = false
    if not isSingleFilled then
        isForageOk = true
        for _, mixerWagonFillType in pairs(self.mixerWagonFillTypes) do
            if mixerWagonFillType.fillLevel < mixerWagonFillType.minPercentage * newFillLevel - 0.01 or mixerWagonFillType.fillLevel > mixerWagonFillType.maxPercentage * newFillLevel + 0.01 then
                isForageOk = false
                break
            end
        end
    end

    self.forageOk = isForageOk
    self.isSingleFilled = isSingleFilled

    if isForageOk then
        if MixerWagonFixLoaded and self.mixingTimePercentage >= 1 then
            newFillType = FillUtil.FILLTYPE_FORAGE
        else
            newFillType = FillUtil.FILLTYPE_FORAGE_MIXING
        end
    elseif not isSingleFilled then
        newFillType = FillUtil.FILLTYPE_FORAGE_MIXING
    end

    superFuncExtra(self, fillUnitIndex, newFillLevel, newFillType, true, fillInfo)

    self:raiseDirtyFlags(self.mixerWagonDirtyFlag)
end

-- -- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

MixerWagonFix_DecayEvent = {}
local MixerWagonFix_DecayEvent_mt = Class(MixerWagonFix_DecayEvent, Event)

InitEventClass(MixerWagonFix_DecayEvent, "MixerWagonFix_DecayEvent")

function MixerWagonFix_DecayEvent:emptyNew()
    local self = Event:new(MixerWagonFix_DecayEvent_mt)
    return self
end

function MixerWagonFix_DecayEvent:new(object, mixingTime, settleTime)
    local self = MixerWagonFix_DecayEvent:emptyNew()
    self.object = object
    self.mixingTime = mixingTime
    self.settleTime = settleTime
    return self
end

function MixerWagonFix_DecayEvent:readStream(streamId, connection)
    self.object = readNetworkNodeObject(streamId)
    self.mixingTime = streamReadFloat32(streamId)
    self.settleTime = streamReadFloat32(streamId)
    self:run(connection)
end

function MixerWagonFix_DecayEvent:writeStream(streamId, connection)
    writeNetworkNodeObject(streamId, self.object)
    streamWriteFloat32(streamId, self.mixingTime)
    streamWriteFloat32(streamId, self.settleTime)
end

function MixerWagonFix_DecayEvent:run(connection)
    if not connection:getIsServer() then
        g_server:broadcastEvent(self, false, connection, self.object)
    end

    self.object.currentMixingTime = self.mixingTime
    self.object.currentSettleTime = self.settleTime
end

function MixerWagonFix_DecayEvent.sendEvent(object, mixingTime, settleTime, noEventSend)
    if noEventSend == nil or noEventSend == false then
        if g_server ~= nil then
            g_server:broadcastEvent(MixerWagonFix_DecayEvent:new(object, mixingTime, settleTime), nil, nil, object)
        else
            g_client:getServerConnection():sendEvent(MixerWagonFix_DecayEvent:new(object, mixingTime, settleTime))
        end
    end
end