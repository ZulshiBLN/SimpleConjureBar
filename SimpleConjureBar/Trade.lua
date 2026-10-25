-- SimpleConjureBar - trade water and food to the target (middle click on Water or Food)
-- Mana users get water and food, everyone else food only, each the best rank the target can use.

local _, ns = ...
if not ns.enabled then return end

local D, L, API = ns.D, ns.L, ns.API
local ItemCount, ItemName = API.ItemCount, API.ItemName
local IsDemo, Print, DemoPrint = ns.IsDemo, ns.Print, ns.DemoPrint

-- Bag API (Retail: C_Container, Classic: globals)
local NumSlots   = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
local PickupItem = (C_Container and C_Container.PickupContainerItem) or PickupContainerItem
local function SlotInfo(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info then return info.itemID, info.stackCount end
        return
    end
    local _, count = GetContainerItemInfo(bag, slot)
    return GetContainerItemID(bag, slot), count
end
local LAST_BAG = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
local TRADE_SLOTS = 6 -- slot 7 is "will not be traded"

-- Largest stack of an item in the bags
local function LargestStack(itemID)
    local bestBag, bestSlot, bestCount
    for bag = 0, LAST_BAG do
        for slot = 1, (NumSlots(bag) or 0) do
            local id, count = SlotInfo(bag, slot)
            if id == itemID and count and (not bestCount or count > bestCount) then
                bestBag, bestSlot, bestCount = bag, slot, count
            end
        end
    end
    return bestBag, bestSlot, bestCount
end

-- Highest rank in the bags the target can already use
local function BestItemForLevel(list, level)
    for _, id in ipairs(list) do
        if (ItemCount(id) or 0) > 0 and ns.ItemMinLevel(id) <= level then return id end
    end
end

local pendingTrade -- { items = { itemID, ... }, guid = partner GUID, expires = time }

local function GiveToTarget()
    local unit = "target"
    if InCombatLockdown() then Print(L.TRADE_COMBAT) return end
    if not UnitExists(unit) or not UnitIsPlayer(unit) or UnitIsUnit(unit, "player")
        or not UnitIsFriend("player", unit) then
        Print(L.TRADE_NO_TARGET)
        return
    end

    local name = UnitName(unit)
    local level = UnitLevel(unit) or 1
    if level < 1 then level = UnitLevel("player") end -- unknown level (??)
    local _, classFile = UnitClass(unit)
    local wantsWater = D.MANA_CLASSES[classFile] or false

    local items, missing = {}, {}
    local waterId = wantsWater and BestItemForLevel(D.WATER_ITEMS, level)
    local foodId  = BestItemForLevel(D.FOOD_ITEMS, level)
    if wantsWater then
        if waterId then items[#items + 1] = waterId else missing[#missing + 1] = L.WATER end
    end
    if foodId then items[#items + 1] = foodId else missing[#missing + 1] = L.FOOD end

    if #missing > 0 then
        Print(L.TRADE_MISSING:format(table.concat(missing, L.AND), name, level))
    end
    if #items == 0 then return end

    if IsDemo() then
        for _, id in ipairs(items) do
            local _, _, count = LargestStack(id)
            DemoPrint(L.DEMO_GIVE, name, math.min(count or 20, 20), ItemName(id) or L.ITEM)
        end
        return
    end

    if CheckInteractDistance and CheckInteractDistance(unit, 2) == false then
        Print(L.TRADE_RANGE:format(name))
        return
    end

    -- The partner is identified by GUID (unique across realms); it is only kept in memory
    pendingTrade = { items = items, guid = UnitGUID(unit), expires = GetTime() + 10 }
    InitiateTrade(unit)
end

-- Once the trade window is open: put the largest stacks in.
-- Only for the player that was middle-clicked (the trade partner is the "NPC" unit).
local function FillTrade()
    local p = pendingTrade
    pendingTrade = nil
    if not p or GetTime() > p.expires then return end
    local partner = UnitGUID("NPC")
    -- a secret GUID cannot be compared: no trade is filled then
    if ns.IsSecret(partner) or ns.IsSecret(p.guid) then return end
    if not p.guid or not partner or partner ~= p.guid then return end

    local slotIndex = 1
    for _, id in ipairs(p.items) do
        -- next free trade slot
        while slotIndex <= TRADE_SLOTS and GetTradePlayerItemLink(slotIndex) do slotIndex = slotIndex + 1 end
        if slotIndex > TRADE_SLOTS then break end
        local bag, slot, count = LargestStack(id)
        if bag then
            ClearCursor()
            PickupItem(bag, slot)
            ClickTradeButton(slotIndex)
            Print(L.TRADE_PUT:format(count, ItemName(id) or L.ITEM))
            slotIndex = slotIndex + 1
        end
    end
    Print(L.TRADE_CONFIRM)
end

local function OnMiddleClick(_, btn, down)
    if btn == "MiddleButton" and not down then GiveToTarget() end
end
ns.buttons.Water:HookScript("OnClick", OnMiddleClick)
ns.buttons.Food:HookScript("OnClick", OnMiddleClick)

local events = CreateFrame("Frame")
events:RegisterEvent("TRADE_SHOW")
events:RegisterEvent("TRADE_CLOSED")
events:SetScript("OnEvent", function(_, event)
    if event == "TRADE_SHOW" then
        FillTrade()
    else
        pendingTrade = nil
    end
end)
