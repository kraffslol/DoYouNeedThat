local AddonName, AddOn = ...

local _G, pairs, print, gsub, sfind, tinsert = _G, pairs, print, string.gsub, string.find, table.insert
local GetItemInfo, IsEquippableItem, GetInventoryItemLink, UnitClass, GetItemInfoInstant = GetItemInfo, IsEquippableItem, GetInventoryItemLink, UnitClass, GetItemInfoInstant
local GameTooltip, SendChatMessage, UIParent, ShowUIPanel, select = GameTooltip, SendChatMessage, UIParent, ShowUIPanel, select
local UnitGUID, IsInRaid, GetNumGroupMembers, GetInstanceInfo = UnitGUID, IsInRaid, GetNumGroupMembers, GetInstanceInfo
local C_Timer, GetPlayerInfoByGUID, InCombatLockdown, time = C_Timer, GetPlayerInfoByGUID, InCombatLockdown, time
local UnitIsConnected, CanInspect, UnitName = UnitIsConnected, CanInspect, UnitName
local WEAPON, ARMOR = WEAPON, ARMOR
local LOOT_ITEM_PATTERN = gsub(LOOT_ITEM, '%%s', '(.+)')
local LibItemLevel = LibStub("LibItemLevel")
local LibInspect = LibStub("LibInspect")
local _, playerClass = UnitClass("player")

--[[ 
	TODO: 
		* OnItemRecieved remove item from list?
		* ENCOUNTER_LOOT_RECEIVED
			encounterID, itemID, itemLink, quantity, playerName, className
			https://github.com/tomrus88/BlizzardInterfaceCode/blob/master/Interface/FrameXML/LevelUpDisplay.lua#L1450-L1468
		* 8.0 Look into Item class (ContinueOnItemLoad Usage: NonEmptyItem:ContinueOnLoad(callbackFunction))
		* Test: DoesItemContainSpec(link, classID)
		* RaidMembers cleanup
		* Config/Options frame
		* 5-man group inspect
--]]

AddOn.MainFrame = CreateFrame("Frame", nil, UIParent);
AddOn.db = {}
AddOn.Events = {}
AddOn.Entries = {}
AddOn.RaidMembers = {}
AddOn.inspectCount = 1
AddOn.Config = {}
AddOn.lootFrameOpen = false
-- AddOn.entriesIndex = 1

DoYouNeedThat = AddOn

function AddOn.Print(msg)
	print("[|cff3399FFDYNT|r] " .. msg)
end

function AddOn.Debug(msg)
	if (AddOn.Config.debug) then AddOn.Print(msg) end
end

-- Events: CHAT_MSG_LOOT, ENCOUNTER_END
function AddOn.Events:CHAT_MSG_LOOT(...)
	local message, _, _, _, looter = ...
	local _, item = message:match(LOOT_ITEM_PATTERN)

	if not item then return end
	if not IsEquippableItem(item) then return end

	local _, _, rarity, _, _, type, _, _, equipLoc, _, _, itemClass, itemSubClass = GetItemInfo(item)

	-- If not Armor/Weapon or if its a Legendary return
	if (type ~= ARMOR and type ~= WEAPON) or (rarity == 5) then return end
	-- If not equippable by your class return
	--if not AddOn:IsEquippableForClass(itemClass, itemSubClass, equipLoc) then return end

	local _, iLvl = LibItemLevel:GetItemInfo(item)

	AddOn.Debug(item .. " " .. iLvl)

	--if AddOn.IsItemUpgrade(iLvl, equipLoc) then
		--AddOn.Print("Item is upgrade")
		if not sfind(looter, '-') then
			looter = AddOn.Utils.GetUnitNameWithRealm(looter)
			AddOn.Debug(looter)
		end
		AddOn.Debug(looter)
		local t = {item, looter, iLvl}
		AddOn.Debug(t[1] .. " " .. t[2] .. " " .. t[3])
		AddOn:AddItemToLootTable(t)
	--end
end

function AddOn.Events:ENCOUNTER_END(...)
	local _, _, _, _, success = ...
	local _, _, difficulty = GetInstanceInfo()
	AddOn:ClearEntries()
	if AddOn.Config.openAfterEncounter and success and difficulty ~= 8 then AddOn.lootFrame:Show() end
end

function AddOn.Events:PLAYER_ENTERING_WORLD()
	--AddOn.MainFrame:RegisterEvent("CHAT_MSG_LOOT")
	local _, instanceType = GetInstanceInfo()
	if instanceType == "none" then
		AddOn.Debug("Not in instance, unregistering events")
		AddOn.MainFrame:UnregisterEvent("CHAT_MSG_LOOT")
		AddOn.MainFrame:UnregisterEvent("ENCOUNTER_END")
		return
	end
	AddOn.Debug("In instance, registering events")
	AddOn.MainFrame:RegisterEvent("CHAT_MSG_LOOT")
	AddOn.MainFrame:RegisterEvent("ENCOUNTER_END")
end

function AddOn.Events:ADDON_LOADED(addon)
	if not addon == AddonName then return end
	AddOn.MainFrame:UnregisterEvent("ADDON_LOADED")

	if DyntDB == nil then
		DyntDB = {
			lootWindow = {"CENTER", 0, 0},
			config = {
				whisperMessage = "Do you need [item]?",
				openAfterEncounter = true,
				debug = false
			}
		}
	end

	AddOn.db = DyntDB

	-- Set window position
	AddOn.lootFrame:SetPoint(AddOn.db.lootWindow[1], AddOn.db.lootWindow[2], AddOn.db.lootWindow[3])
	-- Replace config with saved one
	AddOn.Config = AddOn.db.config

	-- TODO: Move this to PLAYER_ENTERING_WORLD, Only start it if you are in raid/dungeon, Cancel it if not
	-- Set repeated timer to check for raidmembers inventory
	local ticker = C_Timer.NewTicker(7, function() AddOn.InspectGroup() end)
end

function AddOn.GetEquippedIlvlBySlotID(slotID)
	local item = GetInventoryItemLink('player', slotID)
	local _, iLvl = LibItemLevel:GetItemInfo(item)
	return iLvl
end

function AddOn.IsItemUpgrade(ilvl, equipLoc)
	if ilvl ~= nil and equipLoc ~= nil and equipLoc ~= '' then
		-- Evaluate item. If ilvl > your current ilvl
		if equipLoc == 'INVTYPE_FINGER' then
			local eqIlvl1 = AddOn.GetEquippedIlvlBySlotID(11)
			local eqIlvl2 = AddOn.GetEquippedIlvlBySlotID(12)
			if eqIlvl1 < ilvl or eqIlvl2 < ilvl then return true end
		elseif equipLoc == 'INVTYPE_TRINKET' then
			local eqIlvl1 = AddOn.GetEquippedIlvlBySlotID(13)
			local eqIlvl2 = AddOn.GetEquippedIlvlBySlotID(14)
			if eqIlvl1 < ilvl or eqIlvl2 < ilvl then return true end
		elseif equipLoc == 'INVTYPE_WEAPON' then
			local eqIlvl1 = AddOn.GetEquippedIlvlBySlotID(16)
			local eqIlvl2 = AddOn.GetEquippedIlvlBySlotID(17)
			if eqIlvl1 < ilvl or eqIlvl2 < ilvl then return true end
		else
			local slotID = AddOn.Utils.GetSlotID(equipLoc)
			local eqIlvl = AddOn.GetEquippedIlvlBySlotID(slotID)
			if eqIlvl < ilvl then return true end
		end
	end
	return false
end

function AddOn:IsEquippableForClass(itemClass, itemSubClass, equipLoc)
	-- Can be equipped by all, return true without checking
	if equipLoc == 'INVTYPE_CLOAK' or equipLoc == 'INVTYPE_FINGER' or equipLoc == 'INVTYPE_TRINKET' then return true end
	
	local classGear = self.Utils.ValidGear[playerClass]
	-- Loop through equippable item classes, if a match is found return true
	for i=1, #classGear[itemClass] do
		if itemSubClass == classGear[itemClass][i] then return true end
	end

	return false
end

function AddOn:ClearEntries()
	for i = 1, #self.Entries do
		if self.Entries[i].itemLink then
			self.Entries[i]:Hide()
			self.Entries[i].itemLink = nil
			self.Entries[i].looter = nil
			self.Entries[i].guid = nil
		end
	end
end

function AddOn:GetEntry(itemLink, looter)
	local entry = nil
	for i = 1, #self.Entries do
		-- If it already exists
		if self.Entries[i].itemLink == itemLink and self.Entries[i].looter == looter then
			return self.Entries[i]
		end

		-- Otherwise return a new one
		if not self.Entries[i].itemLink then
			return self.Entries[i]
		end
	end
end

function AddOn:AddItemToLootTable(t)
	-- Itemlink, Looter, Ilvl
	AddOn.Debug("Adding item to entries")
	local entry = self:GetEntry(t[1], t[2])
	local _, _, _, equipLoc, texture = GetItemInfoInstant(t[1])
	local character = t[2]:match("(.*)%-") or t[2]

	entry.itemLink = t[1]
	entry.looter = t[2]
	entry.guid = UnitGUID(character)
	
	-- If looter has been inspected, show their equipped items in those slots
	if AddOn.RaidMembers[entry.guid] ~= nil then
		local raidMember = AddOn.RaidMembers[entry.guid]
		local item, item2 = nil, nil
		if equipLoc == "INVTYPE_FINGER" then 
			item, item2 = raidMember.items[11], raidMember.items[12]
		elseif equipLoc == "INVTYPE_TRINKET" then
			item, item2 = raidMember.items[13], raidMember.items[14]
		else
			local slotId = AddOn.Utils.GetSlotID(equipLoc)
			item = raidMember.items[slotId]
		end
		AddOn.setItemTooltip(entry.looterEq1, item)
		if item2 ~= nil then AddOn.setItemTooltip(entry.looterEq2, item2) end
	end

	entry.name:SetText(character)
	AddOn.setItemTooltip(entry.item, t[1])
	entry.ilvl:SetText(t[3])

	self:repositionFrames()

	entry.whisper:Show()
	entry:Show()
end

function AddOn.ShowItemTooltip(itemLink)
	ShowUIPanel(GameTooltip)
	GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
	GameTooltip:SetHyperlink(itemLink)
	GameTooltip:Show()
end

function AddOn.HideItemTooltip()
	GameTooltip:Hide()
end

function AddOn.SendWhisper(itemLink, looter)
	-- Replace [item] with itemLink if supplied
	local message = AddOn.Config.whisperMessage:gsub("%[item%]", itemLink)

	AddOn.Debug(looter .. " " .. message)
	SendChatMessage(message, "WHISPER", nil, looter)
end

function AddOn.InspectPlayer(unit)
	if not (UnitIsConnected(unit) and CanInspect(unit) and not InCombatLockdown()) then
		return false
	end

	local canInspect, unitFound = LibInspect:RequestData("items", unit, false)
	if not canInspect or not unitFound then 
		return false
	end
	return true
end

function AddOn.InspectGroup()
	local isInRaid = IsInRaid()
	if not isInRaid and not IsInGroup() or InCombatLockdown() then return end
	--local max = isInRaid and 40 or 5
	local max = GetNumGroupMembers()
	local unit = isInRaid and "raid" or "party"
	local i = AddOn.inspectCount
	local curTime = time()

	while i <= max do
		local guid = UnitGUID(unit..i)
		if (AddOn.RaidMembers[guid] == nil or AddOn.RaidMembers[guid].maxAge <= curTime) and AddOn.InspectPlayer(unit..i) then
			--AddOn.Debug("New character to inspect " .. 	i)
			break
		end
		i = i + 1
	end
	--  GetNumGroupMembers() "group"..i

	i = i + 1
	if i > max then
		i = 1
	end
	AddOn.inspectCount = i
end

LibInspect:SetMaxAge(599)
LibInspect:AddHook(AddonName, "items", function(guid, data, age)
	if data then
		local _, _, _, _, _, name, realm = GetPlayerInfoByGUID(guid)
		--AddOn.Debug(name .. "-" .. realm)
		AddOn.RaidMembers[guid] = {
			items = data.items,
			maxAge = time() + 600
		}
	end
end)

-- Event handler
AddOn.MainFrame:SetScript("OnEvent", function(self, event, ...) AddOn.Events[event](self, ...) end)

AddOn.MainFrame:RegisterEvent("ADDON_LOADED")
AddOn.MainFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

local function SlashCommandHandler(msg)
	local _, _, cmd, args = sfind(msg, "%s?(%w+)%s?(.*)")
	if cmd == "clear" then
		AddOn:ClearEntries()
	elseif cmd == "test" and args ~= "" then
		local player = UnitName("player")
		local item = {args, player}
		local _, iLvl = LibItemLevel:GetItemInfo(args)
		item[3] = iLvl
		--[[local guid = UnitGUID("player")
		AddOn.RaidMembers[guid] = {
			items = {
				[11] = "\124cffff8000\124Hitem:132452::::::::110:::::\124h[Sephuz's Secret]\124h\124r"
			}
		}]]
		LibInspect:RequestData("items", "player", false)
		AddOn:AddItemToLootTable(item)
	elseif cmd == "debug" then
		AddOn.Config.debug = not AddOn.Config.debug
		AddOn.Print("Debug mode " .. (AddOn.Config.debug and "enabled" or "disabled"))
	else
		if not AddOn.lootFrameOpen then
			AddOn.lootFrame:Show()
			AddOn.lootFrameOpen = true
		else
			AddOn.lootFrame:Hide()
			AddOn.lootFrameOpen = false
		end		
	end
end

SLASH_DYNT1 = "/dynt"
SLASH_DYNT2 = "/doyouneedthat"
SlashCmdList["DYNT"] = SlashCommandHandler