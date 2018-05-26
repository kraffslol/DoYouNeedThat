local AddonName, AddOn = ...

local _G, pairs, print, gsub, sfind, tinsert = _G, pairs, print, string.gsub, string.find, table.insert
local GetItemInfo, IsEquippableItem, GetInventoryItemLink, UnitClass = GetItemInfo, IsEquippableItem, GetInventoryItemLink, UnitClass
local GameTooltip, SendChatMessage, UIParent, ShowUIPanel = GameTooltip, SendChatMessage, UIParent, ShowUIPanel
local WEAPON, ARMOR = WEAPON, ARMOR
local LOOT_ITEM_PATTERN = gsub(LOOT_ITEM, '%%s', '(.+)')
local LibItemLevel = LibStub("LibItemLevel")
local Utils = AddOn.Utils
local _, playerClass = UnitClass("player")

AddOn.MainFrame = CreateFrame("Frame", nil, UIParent);
AddOn.Events = {}
AddOn.Entries = {}
AddOn.Config = {
	whisperMessage = "Do you need that?",
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
	if not AddOn:IsEquippableForClass(itemClass, itemSubClass, equipLoc) then return end

	local _, iLvl = LibItemLevel:GetItemInfo(item)

	AddOn.Debug(item .. " " .. iLvl)

	--if AddOn.IsItemUpgrade(iLvl, equipLoc) then
		--AddOn.Print("Item is upgrade")
		-- TODO: Get looter and item and add to AddOn.Loot table.
		if not sfind(looter, '-') then
			looter = AddOn.Util.GetUnitNameWithRealm(looter)
		end
		AddOn.AddItemToLootTable({item, looter, iLvl})
	--end
end

function AddOn.Events:ENCOUNTER_END()
	AddOn:ClearEntries()
	if AddOn.Config.openAfterEncounter then AddOn.lootFrame:Show() end
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

function AddOn:ClearEntries()
	for i = 1, #self.Entries do
		if self.Entries[i].itemLink then
			self.Entries[i]:Hide()
			self.Entries[i].itemLink = nil
			self.Entries[i].looter = nil
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
	local entry = self:GetEntry(t[1], t[2])
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
	SendChatMessage(AddOn.Config.whisperMessage, "WHISPER", nil, looter)
end

-- Event handler
AddOn.MainFrame:SetScript("OnEvent", function(self, event, ...) AddOn.Events[event](self, ...) end)

-- Register events
for k, v in pairs(AddOn.Events) do AddOn.MainFrame:RegisterEvent(k) end

local function SlashCommandHandler(msg)
	local _, _, cmd, args = sfind(msg, "%s?(%w+)%s?(.*)")
	if cmd == "clear" then
		AddOn:ClearEntries()
	elseif cmd == "test" and args ~= "" then
		local item = {args, "Pepe", 929}
		AddOn:AddItemToLootTable(item)
	else
		AddOn.lootFrame:Show()
	end
end

SLASH_DYNT1 = "/dynt"
SlashCmdList["DYNT"] = SlashCommandHandler