-- ============================================================
-- PoisonAlert - Aviso visual cuando el veneno del arma se agota
-- v3.0: Código unificado y verificado
-- ============================================================

local frame = CreateFrame("Frame")
local icon = CreateFrame("Button", "PoisonAlertIcon", UIParent)

local ICON_SIZE = 64
local CHECK_INTERVAL = 1
local POISON_ICON = "Interface\\Icons\\Ability_PoisonSting"
local SLOT_MAINHAND = 16
local SLOT_OFFHAND = 17
local QUESTION_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

-- IDs de los ÍTEMS de veneno (Los que me pasaste)
local VALID_POISON_ITEMS = {
    [6947] = true,   -- Veneno instantáneo
    [6949] = true,   -- Veneno instantáneo II
    [6950] = true,   -- Veneno instantáneo III
    [8926] = true,   -- Veneno instantáneo IV
    [8927] = true,   -- Veneno instantáneo V
    [8928] = true,   -- Veneno instantáneo VI
    [2892] = true,   -- Veneno mortal
    [2893] = true,   -- Veneno mortal II
    [8984] = true,   -- Veneno mortal III
    [8985] = true,   -- Veneno mortal IV
    [20844] = true,  -- Veneno mortal V
}

local db
local function InitDB()
    if not ApoisonAlertDB then ApoisonAlertDB = {} end
    db = ApoisonAlertDB
end

local function SavePosition()
    if not db then return end
    local point, _, relPoint, x, y = icon:GetPoint(1)
    db.pos = { point = point, relPoint = relPoint, x = x, y = y }
end

local lastEnchantMH, lastEnchantOH
local pulseTime = 0

-- ============================================================
-- FUNCIONES AUXILIARES (Compatibilidad Total)
-- ============================================================

-- Obtener información del item (nombre, link, etc)
local function GetItemInfoSafe(itemLink)
    if C_Item and C_Item.GetItemInfo then
        return C_Item.GetItemInfo(itemLink)
    end
    if GetItemInfo then
        return GetItemInfo(itemLink)
    end
    return nil
end

-- Obtener icono a partir del link
local function GetItemIconFromLink(itemLink)
    if not itemLink then return QUESTION_ICON end
    local itemID = tonumber(itemLink:match("item:(%d+)"))
    if not itemID then return QUESTION_ICON end
    
    if C_Item and C_Item.GetItemIconByID then
        return C_Item.GetItemIconByID(itemID) or QUESTION_ICON
    end
    if GetItemIcon then
        return GetItemIcon(itemID) or QUESTION_ICON
    end
    return QUESTION_ICON
end

-- Obtener número de slots de la bolsa
local function GetBagNumSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then
        return C_Container.GetContainerNumSlots(bag) or 0
    end
    if GetContainerNumSlots then
        return GetContainerNumSlots(bag) or 0
    end
    return 0
end

-- Obtener el link del item en la bolsa
local function GetBagItemLink(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info then return info.hyperlink end
        return nil
    end
    if GetContainerItemLink then
        return GetContainerItemLink(bag, slot)
    end
    return nil
end

-- Obtener textura del arma equipada
local function GetWeaponTexture(slot)
    if GetInventoryItemTexture then
        return GetInventoryItemTexture("player", slot) or POISON_ICON
    end
    return POISON_ICON
end

-- ============================================================
-- ICONO PRINCIPAL
-- ============================================================

icon:SetSize(ICON_SIZE, ICON_SIZE)
icon:SetFrameStrata("HIGH")
icon:SetClampedToScreen(true)
icon:Hide()

local texture = icon:CreateTexture(nil, "ARTWORK")
texture:SetAllPoints()
texture:SetTexture(POISON_ICON)
texture:SetDesaturated(true)

local border = icon:CreateTexture(nil, "OVERLAY")
border:SetPoint("TOPLEFT", -2, 2)
border:SetPoint("BOTTOMRIGHT", 2, -2)
border:SetColorTexture(0, 1, 0, 0.8)

local glow = icon:CreateTexture(nil, "BACKGROUND")
glow:SetPoint("TOPLEFT", -12, 12)
glow:SetPoint("BOTTOMRIGHT", 12, -12)
glow:SetTexture("Interface\\Buttons\\WHITE8X8")
glow:SetVertexColor(0, 1, 0, 0.3)
glow:SetBlendMode("ADD")

local label = icon:CreateFontString(nil, "OVERLAY", "GameFontNormal")
label:SetPoint("TOP", icon, "BOTTOM", 0, -4)
label:SetTextColor(0, 1, 0)

-- Animación
icon:SetScript("OnUpdate", function(self, elapsed)
    pulseTime = pulseTime + elapsed
    local alpha = 0.2 + 0.3 * math.abs(math.sin(pulseTime * 2))
    glow:SetAlpha(alpha)
end)

-- Mover con Shift + arrastrar
icon:RegisterForDrag("LeftButton")
icon:SetMovable(true)
icon:SetScript("OnDragStart", function(self)
    if IsShiftKeyDown() then self:StartMoving() end
end)
icon:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SavePosition()
end)
-- ============================================================
-- MENÚ DESPLEGABLE
-- ============================================================

local menu = CreateFrame("Frame", "PoisonAlertMenu", UIParent)
menu:SetSize(220, 200)
menu:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, 0)
menu:SetFrameStrata("DIALOG")
menu:EnableMouse(true)
menu:Hide()

local bg = menu:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints(menu)
bg:SetColorTexture(0.1, 0.1, 0.1, 0.95)

local borderMenu = menu:CreateTexture(nil, "OVERLAY")
borderMenu:SetPoint("TOPLEFT", -1, 1)
borderMenu:SetPoint("BOTTOMRIGHT", 1, -1)
borderMenu:SetColorTexture(0, 1, 0, 0.5)

local title = menu:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOP", menu, "TOP", 0, -8)
title:SetText("Seleccionar Veneno")
title:SetTextColor(0, 1, 0)

local scrollFrame = CreateFrame("ScrollFrame", nil, menu, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", menu, "TOPLEFT", 10, -30)
scrollFrame:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", -30, 10)

local content = CreateFrame("Frame", nil, scrollFrame)
content:SetSize(160, 1)
scrollFrame:SetScrollChild(content)

local poisonButtons = {}

-- ============================================================
-- FUNCIONES DEL MENÚ
-- ============================================================
-- Devuelve el slot al que aplicar el veneno:
-- falta la principal (o ambas) -> 16 | falta solo la secundaria -> 17
local function GetTargetSlot()
    local hasMH, _, _, _, hasOH = GetWeaponEnchantInfo()
    if not hasMH then return SLOT_MAINHAND end
    if not hasOH then return SLOT_OFFHAND end
    return SLOT_MAINHAND
end

-- ============================================================
-- RUEDA DEL RATÓN: aplicar el último veneno usado
-- ============================================================

local quickBtn = CreateFrame("Button", "PoisonAlertQuickBtn", icon, "SecureActionButtonTemplate")
quickBtn:SetAllPoints(icon)
quickBtn:SetFrameLevel(icon:GetFrameLevel() + 2)
quickBtn:RegisterForClicks("AnyUp", "AnyDown")
quickBtn:RegisterForDrag("LeftButton")

-- Reenviar al icono lo que hacía antes
quickBtn:HookScript("OnClick", function(self, button, down)
    if button == "LeftButton" and not down then
        local fn = icon:GetScript("OnClick")
        if fn then fn(icon, "LeftButton") end
    end
end)
quickBtn:SetScript("OnDragStart", function()
    if IsShiftKeyDown() then icon:StartMoving() end
end)
quickBtn:SetScript("OnDragStop", function()
    icon:StopMovingOrSizing()
    SavePosition()
end)
quickBtn:SetScript("OnEnter", function()
    local fn = icon:GetScript("OnEnter")
    if fn then fn(icon) end
end)
quickBtn:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

local function FindPoisonInBags(itemID)
    for bag = 0, 4 do
        for slot = 1, GetBagNumSlots(bag) do
            local link = GetBagItemLink(bag, slot)
            if link and tonumber(link:match("item:(%d+)")) == itemID then
                return bag, slot
            end
        end
    end
end

local lastQuickKey
function ApoisonAlert_RefreshQuick()
    -- No se pueden cambiar atributos seguros en combate
    if InCombatLockdown() or not db then return end

    -- Mano que falta ahora mismo y último veneno que se puso en ella
    local target = GetTargetSlot()
    local itemID = db.lastPoisonBySlot and db.lastPoisonBySlot[target]
    local bag, slot
    if itemID then bag, slot = FindPoisonInBags(itemID) end

    local key = tostring(bag) .. "-" .. tostring(slot) .. "-" .. target
    if key == lastQuickKey then return end
    lastQuickKey = key

    if bag then
        quickBtn:SetAttribute("type3", "macro")
        quickBtn:SetAttribute("macrotext3",
            string.format("/use %d %d\n/use %d", bag, slot, target))
    else
        quickBtn:SetAttribute("type3", nil)
        quickBtn:SetAttribute("macrotext3", nil)
    end
end

function ApoisonAlert_ScanPoisons()
    -- Limpiar botones antiguos visualmente
    for _, btn in ipairs(poisonButtons) do
        btn:Hide()
        btn:SetParent(nil)
    end
    poisonButtons = {}

    -- Tabla separada para guardar los datos de los venenos encontrados
    local poisonData = {}
    local foundPoisons = {}
    local yOffset = 0
    local targetSlot = GetTargetSlot()
    
    -- Escanear bolsas (0 a 4)
    for bag = 0, 4 do
        local numSlots = GetBagNumSlots(bag)
        for slot = 1, numSlots do
            local itemLink = GetBagItemLink(bag, slot)
            if itemLink then
                local itemID = tonumber(itemLink:match("item:(%d+)"))
                if itemID and VALID_POISON_ITEMS[itemID] then
                    if not foundPoisons[itemID] then
                        foundPoisons[itemID] = true
                        local name = GetItemInfoSafe(itemLink) or ("Veneno " .. itemID)
                        table.insert(poisonData, {
                            bag = bag,
                            slot = slot,
                            name = name,
                            link = itemLink,
                            itemID = itemID
                        })
                    end
                end
            end
        end
    end

    -- Crear botones visuales a partir de los datos
    for i, data in ipairs(poisonData) do
        -- Contenedor visual
        local row = CreateFrame("Button", nil, content)
        row:SetSize(140, 36)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -yOffset)
        yOffset = yOffset + 40

        -- Icono
        local iconTex = row:CreateTexture(nil, "ARTWORK")
        iconTex:SetSize(36, 36)
        iconTex:SetPoint("LEFT", row, "LEFT", 0, 0)
        iconTex:SetTexture(GetItemIconFromLink(data.link))
        iconTex:SetTexCoord(0.07, 0.93, 0.07, 0.93)

        -- Texto
        local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("LEFT", iconTex, "RIGHT", 5, 0)
        text:SetText(data.name)
        text:SetWidth(100)
        text:SetJustifyH("LEFT")

        -- Botón seguro (invisible) que hace la acción real
        local secureBtn = CreateFrame("Button", nil, row, "SecureActionButtonTemplate")
        secureBtn:SetAllPoints(row)
        secureBtn:RegisterForClicks("AnyUp", "AnyDown")
        secureBtn:SetAttribute("type", "macro")
        secureBtn:SetAttribute("macrotext",
            string.format("/use %d %d\n/use %d", data.bag, data.slot, targetSlot))

        secureBtn:SetScript("PostClick", function()
            db.lastPoisonBySlot = db.lastPoisonBySlot or {}
            db.lastPoisonBySlot[targetSlot] = data.itemID   -- se guarda para esa mano (16 o 17)
            ApoisonAlert_RefreshQuick()
            menu:Hide()
        end)

        -- Tooltip (en el botón seguro, que es el que recibe el ratón)
        secureBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(data.name)
            local manoTxt = (targetSlot == SLOT_MAINHAND) and "arma principal" or "arma secundaria"
            GameTooltip:AddLine("Clic para aplicar al " .. manoTxt, 0.6, 1, 0.6)
            GameTooltip:AddLine("Rueda: aplicar el último veneno usado", 1, 0.82, 0)
            GameTooltip:Show()
        end)
        secureBtn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        row:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        
        -- Guardamos el botón en la tabla de botones para poder limpiarlo luego
        table.insert(poisonButtons, row) 
    end

    content:SetHeight(yOffset)
    local menuHeight = math.min(300, yOffset + 40)
    menu:SetSize(220, menuHeight)
end

function ApoisonAlert_ToggleMenu()
    if menu:IsShown() then
        menu:Hide()
    elseif InCombatLockdown() then
        print("|cff00ff00PoisonAlert:|r No se puede abrir el menú en combate")
    else
        ApoisonAlert_ScanPoisons()
        menu:Show()
    end
end

-- ============================================================
-- CLIC EN EL ICONO PRINCIPAL
-- ============================================================

icon:SetScript("OnClick", function(self, button)
    if button == "LeftButton" then
        ApoisonAlert_ToggleMenu()
    end
end)

-- Tooltip del icono principal
icon:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("PoisonAlert")
    GameTooltip:AddLine("Shift + clic y arrastra para mover", 1, 1, 1)
    GameTooltip:AddLine("Clic para abrir el menú de venenos", 0.6, 1, 0.6)
    GameTooltip:AddLine(" ")
    local function Nombre(slot)
        local id = db.lastPoisonBySlot and db.lastPoisonBySlot[slot]
        if not id then return "(ninguno)" end
        return GetItemInfoSafe("item:" .. id) or ("ID " .. id)
    end
    GameTooltip:AddLine("Izquierda: " .. Nombre(SLOT_MAINHAND), 0.8, 0.8, 1)
    GameTooltip:AddLine("Derecha: " .. Nombre(SLOT_OFFHAND), 0.8, 0.8, 1)
    GameTooltip:AddLine("Rueda: aplicar el último de esa mano", 1, 0.82, 0)
    GameTooltip:Show()
end)
icon:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

-- ============================================================
-- POSICIÓN FIJA
-- ============================================================

local function ApplyPosition()
    icon:ClearAllPoints()
    if db and db.pos then
        icon:SetPoint(db.pos.point, UIParent, db.pos.relPoint, db.pos.x, db.pos.y)
    else
        icon:SetPoint("TOP", UIParent, "TOP", 0, -250)
    end
end

-- ============================================================
-- LÓGICA DE DETECCIÓN (CheckPoison)
-- ============================================================

local function CheckPoison()
    local hasMH, _, _, idMH, hasOH, _, _, idOH = GetWeaponEnchantInfo()
    local faltaIzquierda = not hasMH
    local faltaDerecha = not hasOH

    if hasMH and idMH and idMH ~= 0 and lastEnchantMH ~= idMH then
        db.enchantMH = idMH
        lastEnchantMH = idMH
        print("|cff00ff00PoisonAlert:|r Veneno IZQUIERDA aprendido (ID " .. idMH .. ")")
    elseif not hasMH then
        lastEnchantMH = nil
    end

    if hasOH and idOH and idOH ~= 0 and lastEnchantOH ~= idOH then
        db.enchantOH = idOH
        lastEnchantOH = idOH
        print("|cff00ff00PoisonAlert:|r Veneno DERECHA aprendido (ID " .. idOH .. ")")
    elseif not hasOH then
        lastEnchantOH = nil
    end

    -- Mostrar/Ocultar el icono y actualizar textos
    if faltaIzquierda and faltaDerecha then
        texture:SetTexture(POISON_ICON)
        label:SetText("¡AMBAS!")
        icon:Show()
    elseif faltaIzquierda then
        texture:SetTexture(GetWeaponTexture(SLOT_MAINHAND))
        label:SetText("¡IZQUIERDA!")
        icon:Show()
    elseif faltaDerecha then
        texture:SetTexture(GetWeaponTexture(SLOT_OFFHAND))
        label:SetText("¡DERECHA!")
        icon:Show()
    else
        icon:Hide()
    end
    ApoisonAlert_RefreshQuick()
end

-- ============================================================
-- EVENTOS
-- ============================================================

frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("UNIT_INVENTORY_CHANGED")
frame:SetScript("OnEvent", function(self, event, unit)
    if event == "PLAYER_LOGIN" then
        local _, class = UnitClass("player")
        if class ~= "ROGUE" then
            self:UnregisterAllEvents()
            icon:Hide()
            frame:SetScript("OnUpdate", nil)
            return
        end
        InitDB()
        ApplyPosition()
        CheckPoison()
        self.elapsed = 0
    elseif event == "UNIT_INVENTORY_CHANGED" and unit == "player" then
        C_Timer.After(0.5, CheckPoison)
    end
end)

frame:SetScript("OnUpdate", function(self, elapsed)
    self.elapsed = (self.elapsed or 0) + elapsed
    if self.elapsed >= CHECK_INTERVAL then
        self.elapsed = 0
        CheckPoison()
    end
end)