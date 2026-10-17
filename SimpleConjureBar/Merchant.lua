-- SimpleConjureBar - reagent auto-buy
-- At a vendor the missing amount up to the configured target amount is bought,
-- but only for reagents whose spells are known and only as far as the gold reaches.

local _, ns = ...
if not ns.enabled then return end

local D, L, API = ns.D, ns.L, ns.API
local ItemCount, ItemName, MoneyText = API.ItemCount, API.ItemName, API.MoneyText
local IsDemo, IsKnown, Print, DemoPrint = ns.IsDemo, ns.IsKnown, ns.Print, ns.DemoPrint

local db
ns.OnDBReady(function(d) db = d end)

local function ReagentNeeded(r)
    if r.need then return #ns.KnownTravel(r.need) > 0 end
    if r.spell then return IsKnown(r.spell) end
    return true
end

local function MerchantItemID(i)
    if GetMerchantItemID then return GetMerchantItemID(i) end
    local link = GetMerchantItemLink(i)
    return link and tonumber(link:match("item:(%d+)"))
end

local function MerchantPrice(i)
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local info = C_MerchantFrame.GetItemInfo(i)
        if info then return info.price, info.stackCount end
    end
    local _, _, price, qty = GetMerchantItemInfo(i)
    return price, qty
end

local wanted = {}
local BUY_LOCK = 3   -- seconds after a purchase in which no new purchase starts (bags still update)
local lastBuy = -BUY_LOCK

local function AutoBuy()
    -- A vendor closed and reopened right after a purchase: the bag counts may not include the
    -- ordered items yet, so nothing is bought until they did
    if GetTime() - lastBuy < BUY_LOCK then return end
    wipe(wanted)
    for _, r in ipairs(D.REAGENTS) do
        if (db.amounts[r.id] or 0) > 0 and ReagentNeeded(r) then wanted[r.id] = r end
    end

    -- Gold that may be spent: everything above the configured reserve (copper)
    local budget = GetMoney() - db.goldReserve * 10000
    local spent, reserveHit = 0, false
    for i = 1, GetMerchantNumItems() do
        local r = wanted[MerchantItemID(i)]
        if r then
            -- Only the difference to the target amount is bought
            local need = (db.amounts[r.id] or 0) - (ItemCount(r.id) or 0)
            local price, batch = MerchantPrice(i)
            batch = (batch and batch > 0) and batch or 1
            local unit = (price or 0) / batch
            -- Buy less if the budget does not cover the full difference. Items without a gold price
            -- (other currencies) are never bought automatically.
            if unit <= 0 then
                need = 0
            elseif need > 0 then
                local affordable = math.max(0, math.floor((budget - spent) / unit))
                if affordable < need then reserveHit = true end
                need = math.min(need, affordable)
            end
            if need > 0 then
                local name = ns.LocalName(ItemName(r.id), r.nameKey)
                if IsDemo() then
                    DemoPrint(L.DEMO_BUY, need, name)
                else
                    -- At least 1 per call, so the loop always ends
                    local maxStack = math.max(1, math.floor(tonumber(GetMerchantItemMaxStack(i)) or need))
                    local left = need
                    while left > 0 do
                        local n = math.min(left, maxStack)
                        BuyMerchantItem(i, n)
                        left = left - n
                    end
                    -- The purchase is only requested here (it can still fail, e.g. with full bags)
                    Print(L.BUYING:format(need, name))
                    lastBuy = GetTime()
                end
                spent = spent + need * unit
            end
        end
    end
    if reserveHit and db.goldReserve > 0 then
        Print(L.RESERVE_REACHED:format(MoneyText(db.goldReserve * 10000)))
    end
    if spent > 0 then
        if IsDemo() then
            DemoPrint(L.DEMO_COST, MoneyText(math.floor(spent)))
        else
            Print(L.COST:format(MoneyText(math.floor(spent))))
        end
    end
end

-- Some clients fill the vendor list after MERCHANT_SHOW. In that case the purchase runs once
-- on the first MERCHANT_UPDATE instead (never twice, so nothing is bought double).
local waitingForList = false
local events = CreateFrame("Frame")
events:RegisterEvent("MERCHANT_SHOW")
events:RegisterEvent("MERCHANT_UPDATE")
events:RegisterEvent("MERCHANT_CLOSED")
events:SetScript("OnEvent", function(_, event)
    if not db then return end
    if event == "MERCHANT_SHOW" then
        waitingForList = false
        if not db.autoBuy then return end
        if GetMerchantNumItems() > 0 then
            AutoBuy()
        else
            waitingForList = true
        end
    elseif event == "MERCHANT_UPDATE" then
        if waitingForList and GetMerchantNumItems() > 0 then
            waitingForList = false
            if db.autoBuy then AutoBuy() end
        end
    else
        waitingForList = false -- MERCHANT_CLOSED
    end
end)
