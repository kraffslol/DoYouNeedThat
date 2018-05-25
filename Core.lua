local AddonName, AddOn = ...

local _G, pairs, print, gsub, sfind, tinsert = _G, pairs, print, string.gsub, string.find, table.insert
local GetItemInfo, IsEquippableItem, GetInventoryItemLink, UnitClass = GetItemInfo, IsEquippableItem, GetInventoryItemLink, UnitClass
local GameTooltip = GameTooltip
local WEAPON, ARMOR = WEAPON, ARMOR
local LOOT_ITEM_PATTERN = gsub(LOOT_ITEM, '%%s', '(.+)')
local LibItemLevel = LibStub("LibItemLevel")
local Utils = AddOn.Utils
local _, playerClass = UnitClass("player")

AddOn.MainFrame = CreateFrame("Frame", nil, UIParent);
AddOn.Events = {}
AddOn.Entries = {}
AddOn.entriesIndex = 1

DoYouNeedThat = AddOn

-- TODO: Listen on EncounterEnd, Reset Entries on EncounterEnd and open window.

function AddOn.Print(msg)
	print("[|cff3399FFDYNT|r] " .. msg)
end

-- Events: CHAT_MSG_LOOT
function AddOn.Events:CHAT_MSG_LOOT(...)
	local message, _, _, _, looter = ...
	local _, item = message:match(LOOT_ITEM_PATTERN)

	if not item then return end
	if not IsEquippableItem(item) then return end

	local _, _, rarity, _, _, type, _, _, equipLoc, _, _, itemClass, itemSubClass = GetItemInfo(item)

	-- If not Armor/Weapon or if its a Legendary return
	if (type ~= ARMOR and type ~= WEAPON) or (rarity == 5) then return end
	-- If not equippable by your class return
	if not AddOn:IsEquippableForClass(itemClass, itemSubClass, equipLoc) then return end

	local _, iLvl = LibItemLevel:GetItemInfo(item)

	AddOn.Print(item .. " " .. iLvl)

	if AddOn.IsItemUpgrade(iLvl, equipLoc) then
		AddOn.Print("Item is upgrade")
		-- TODO: Get looter and item and add to AddOn.Loot table.
		if not sfind(looter, '-') then
			looter = AddOn.Util.GetUnitNameWithRealm(looter)
		end
		AddOn.AddItemToLootTable({item, looter, iLvl})
	end
end

function AddOn.GetEquippedIlvl(slotID)
	local item = GetInventoryItemLink('player', slotID)
	local _, iLvl = LibItemLevel:GetItemInfo(item)
	return iLvl
end

function AddOn.IsItemUpgrade(ilvl, equipLoc)
	if ilvl ~= nil and equipLoc ~= nil and equipLoc ~= '' then
		-- Evaluate item. If ilvl > your current ilvl
		if equipLoc == 'INVTYPE_FINGER' then
			local eqIlvl1 = AddOn.GetEquippedIlvl(11)
			local eqIlvl2 = AddOn.GetEquippedIlvl(12)
			if eqIlvl1 < ilvl or eqIlvl2 < ilvl then return true end
		elseif equipLoc == 'INVTYPE_TRINKET' then
			local eqIlvl1 = AddOn.GetEquippedIlvl(13)
			local eqIlvl2 = AddOn.GetEquippedIlvl(14)
			if eqIlvl1 < ilvl or eqIlvl2 < ilvl then return true end
		elseif equipLoc == 'INVTYPE_WEAPON' then
			local eqIlvl1 = AddOn.GetEquippedIlvl(16)
			local eqIlvl2 = AddOn.GetEquippedIlvl(17)
			if eqIlvl1 < ilvl or eqIlvl2 < ilvl then return true end
		else
			local slotID = AddOn.Utils.GetSlotID(equipLoc)
			local eqIlvl = AddOn.GetEquippedIlvl(slotID)
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

function AddOn:AddItemToLootTable(t)
	-- Itemlink, Looter, Ilvl
	local entry = self.Entries[self.entriesIndex]
	local _, link1, _, _, _, _, _, _, _, texture1 = GetItemInfo(t[1])

	entry.itemLink = t[1]
	entry.looter = t[2]

	entry.name:SetText(t[2])
	entry.item.tex:SetTexture(texture1)
	entry.item:SetScript("OnEnter", function()
		ShowUIPanel(GameTooltip)
		GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
		GameTooltip:SetHyperlink(link1)
		GameTooltip:Show()
	end)
	entry.item:SetScript("OnLeave", function() GameTooltip:Hide() end)
	entry.ilvl:SetText(t[3])

	entry:Show()

	self.entriesIndex = self.entriesIndex + 1
end

function AddOn.SendWhisper(itemLink, looter)
	SendChatMessage("Hey do you need that?", "WHISPER", nil, looter)
end

-- Event handler
AddOn.MainFrame:SetScript("OnEvent", function(self, event, ...) AddOn.Events[event](self, ...) end)

-- Register events
for k, v in pairs(AddOn.Events) do AddOn.MainFrame:RegisterEvent(k) end

SLASH_DYNT1 = "/dynt"
SlashCmdList["DYNT"] = function()
	AddOn.lootFrame:Show()
end

SLASH_DYNTTEST1 = "/dynttest"
SlashCmdList["DYNTTEST"] = function(msg)
	local item = {msg, "Pepe", 929}
	AddOn:AddItemToLootTable(item)
end