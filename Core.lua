local AddonName, AddOn = ...

local _G, pairs, print, gsub, sfind, tinsert = _G, pairs, print, string.gsub, string.find, table.insert
local GetItemInfo, IsEquippableItem, GetInventoryItemLink, UnitClass, GetItemInfoInstant = GetItemInfo, IsEquippableItem, GetInventoryItemLink, UnitClass, GetItemInfoInstant
local GameTooltip, SendChatMessage, UIParent, ShowUIPanel, select = GameTooltip, SendChatMessage, UIParent, ShowUIPanel, select
local WEAPON, ARMOR = WEAPON, ARMOR
local LOOT_ITEM_PATTERN = gsub(LOOT_ITEM, '%%s', '(.+)')
local LibItemLevel = LibStub("LibItemLevel")
local LibInspect = LibStub("LibInspect")
local Utils = AddOn.Utils
local _, playerClass = UnitClass("player")

--[[ 
	TODO: 
		* OnItemRecieved remove item from list?
		* ENCOUNTER_LOOT_RECEIVED
			encounterID, itemID, itemLink, quantity, playerName, className
			https://github.com/tomrus88/BlizzardInterfaceCode/blob/master/Interface/FrameXML/LevelUpDisplay.lua#L1450-L1468
		* Look up looters gear on the slot that was looted. GetInventoryItemLink
			- On raid/party join loop through party and NotifyInspect everyone GROUP_ROSTER_UPDATE
		* 8.0 Look into Item class (ContinueOnItemLoad Usage: NonEmptyItem:ContinueOnLoad(callbackFunction))
		* Test: DoesItemContainSpec(link, classID)
		* Don't trigger CHAT_MSG_LOOT if not in dungeon/raid
--]]

AddOn.MainFrame = CreateFrame("Frame", nil, UIParent);
AddOn.Events = {}
AddOn.Entries = {}
AddOn.RaidMembers = {}
AddOn.Config = {
	whisperMessage = "Do you need [item]?",
	openAfterEncounter = true,
	debug = true
}
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
		-- TODO: Get looter and item and add to AddOn.Loot table.
		if not sfind(looter, '-') then
			looter = AddOn.Util.GetUnitNameWithRealm(looter)
			AddOn.Debug(looter)
		end
		AddOn.Debug(looter)
		AddOn:AddItemToLootTable({item, looter, iLvl})
	--end
end

function AddOn.Events:ENCOUNTER_END(...)
	---- encounter ID, encounter name (localized), difficulty ID, group size, success
	local _, _, _, _, _, success = ...
	AddOn:ClearEntries()
	if AddOn.Config.openAfterEncounter and success then AddOn.lootFrame:Show() end
end

function AddOn.Events:GROUP_ROSTER_UPDATE()
	AddOn.Debug("Fetching raid items")
	AddOn.GetRaidItems()
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
	--local entry = self.Entries[self.entriesIndex]
	AddOn.Debug("Adding item to entries")
	local entry = self:GetEntry(t[1], t[2])
	local _, _, _, equipLoc, texture = GetItemInfoInstant(t[1])
	local character = t[2]:match("(.*)%-")

	entry.itemLink = t[1]
	entry.looter = t[2]
	entry.guid = UnitGUID(character)
	
	-- If looter has been inspected, show their equipped items in those slots
	if AddOn.RaidMembers[entry.guid] ~= nil then
		local raidMember = AddOn.RaidMembers[entry.guid]
		if equipLoc == "INVTYPE_FINGER" then 
			local item = raidMember.items[11]
			local item2 = raidMember.items[12]
			local tex = select(5, GetItemInfoInstant(item))
			local tex2 = select(5, GetItemInfoInstant(item2))
			entry.looterEq1.tex:SetTexture(tex)
			entry.looterEq2.tex:SetTexture(tex2)
			entry.looterEq2:Show()
		elseif equipLoc == "INVTYPE_TRINKET" then
			local item = raidMember.items[13]
			local item2 = raidMember.items[14]
			local tex = select(5, GetItemInfoInstant(item))
			local tex2 = select(5, GetItemInfoInstant(item2))
			entry.looterEq1.tex:SetTexture(tex)
			entry.looterEq2.tex:SetTexture(tex2)
			entry.looterEq2:Show()
		else
			local slotId = AddOn.Utils.GetSlotID(equipLoc)
			local item = raidMember.items[slotId]
			AddOn.Debug(item)
			local tex = select(5, GetItemInfoInstant(item))
			entry.looterEq1.tex:SetTexture(tex)
		end
	end

	entry.name:SetText(character)
	entry.item.tex:SetTexture(texture)
	entry.item:SetScript("OnEnter", function()
		ShowUIPanel(GameTooltip)
		GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
		GameTooltip:SetHyperlink(t[1])
		GameTooltip:Show()
	end)
	entry.item:SetScript("OnLeave", function() GameTooltip:Hide() end)
	entry.ilvl:SetText(t[3])

	self:repositionFrames()

	entry.whisper:Show()
	entry:Show()

	-- Instead of index use a forloop and check for a free one (If itemLink == null)
	--[[local newIndex = self.entriesIndex + 1
	if newIndex == 20 then
		AddOn.Print("Reseting index")
		self.entriesIndex = 1
	else
		self.entriesIndex = newIndex
	end--]]
end

function AddOn.SendWhisper(itemLink, looter)
	-- Replace [item] with itemLink if supplied
	local message = AddOn.Config.whisperMessage:gsub("%[item%]", itemLink)

	AddOn.Debug(looter .. " " .. message)
	SendChatMessage(message, "WHISPER", nil, looter)
end

function AddOn.GetRaidItems()
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do
			local guid = UnitGUID("raid"..i)
			LibInspect:RequestData("items", "raid"..i, false)
		end
	else
		for i = 1, GetNumGroupMembers() do
			local guid = UnitGUID("group"..i)
			LibInspect:RequestData("items", "group"..i, false)
		end
	end
end

LibInspect:AddHook("DoYouNeedThat", "items", function(guid, data, age) 
	AddOn.Debug(guid)
	if data then
		-- Update table row here?
		AddOn.RaidMembers[guid] = {
			items = data.items
		}
	end
end)

-- Event handler
AddOn.MainFrame:SetScript("OnEvent", function(self, event, ...) AddOn.Events[event](self, ...) end)

-- Register events
for k, v in pairs(AddOn.Events) do AddOn.MainFrame:RegisterEvent(k) end

local function SlashCommandHandler(msg)
	local _, _, cmd, args = sfind(msg, "%s?(%w+)%s?(.*)")
	if cmd == "clear" then
		AddOn:ClearEntries()
	elseif cmd == "test" and args ~= "" then
		local item = {args, "Lootcouncil-TarrenMill", 929}
		--local guid = UnitGUID("player")
		--[[AddOn.RaidMembers[guid] = {
			name = "Lootcouncil",
			items = {
			[11] = "\124cffff8000\124Hitem:137049::::::::110:::::\124h[Insignia of Ravenholdt]\124h\124r"
			}
		}]]
		AddOn:AddItemToLootTable(item)
	else
		AddOn.lootFrame:Show()
	end
end

SLASH_DYNT1 = "/dynt"
SLASH_DYNT2 = "/doyouneedthat"
SlashCmdList["DYNT"] = SlashCommandHandler