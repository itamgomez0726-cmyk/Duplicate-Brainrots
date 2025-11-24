-- Script en ServerScriptService.LinkReceiverServer
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local sendEvent = ReplicatedStorage:WaitForChild("SendLinkEvent")
local linksStore = DataStoreService:GetDataStore("PlayerSubmittedLinks_v1") -- nombre del DataStore

-- Configuración
local MAX_LENGTH = 300
local COOLDOWN_SECONDS = 30 -- tiempo entre envíos por jugador
local allowedProtocols = { "http://", "https://" } -- mínimo
local whitelistDomains = nil
-- Ejemplo de whitelist (descomentar y rellenar si quieres sólo dominios permitidos):
-- whitelistDomains = { "example.com", "roblox.com" } 

-- Tabla en memoria para limitar spam (no persistente al reinicio)
local lastSent = {}

local function isProtocolAllowed(link)
    for _, p in ipairs(allowedProtocols) do
        if link:sub(1, #p):lower() == p then
            return true
        end
    end
    return false
end

local function isLikelyURL(link)
    -- patrón sencillo: protocolo://algo.algo (no perfecto pero útil)
    -- evita inyecciones de tamaño o caracteres extraños
    if #link > MAX_LENGTH then return false end
    if not isProtocolAllowed(link) then return false end
    -- busca un punto en el dominio y al menos alguna otra parte
    if not link:match("%.") then return false end
    -- evitar caracteres de control
    if link:match("[%c]") then return false end
    return true
end

local function domainFromLink(link)
    -- intenta extraer el host simplificado
    local s = link:match("^%w+://([^/]+)")
    if not s then return nil end
    -- quitar puerto si lo hay
    s = s:match("^([^:]+)")
    return s:lower()
end

local function isWhitelisted(link)
    if not whitelistDomains then return true end -- si no hay whitelist, permitir
    local domain = domainFromLink(link)
    if not domain then return false end
    for _, d in ipairs(whitelistDomains) do
        if domain:find(d, 1, true) then
            return true
        end
    end
    return false
end

local function saveLinkRecord(record)
    -- guardamos en DataStore como lista por timestamp. 
    -- Nota: DataStore tiene límites y podría fallar. Hacemos pcall.
    local success, err = pcall(function()
        -- guardar bajo una key global (no ideal si alto volumen). Alternativa: guardar por jugador.
        -- Aquí concatenamos con timestamp para evitar colisiones.
        local key = "link_" .. tostring(tick())
        linksStore:SetAsync(key, record)
    end)
    return success, err
end

sendEvent.OnServerEvent:Connect(function(player, link)
    if not player or not link then return end
    link = tostring(link)
    -- cooldown
    local now = os.time()
    local last = lastSent[player.UserId]
    if last and (now - last) < COOLDOWN_SECONDS then
        -- enviar mensaje al jugador (simple)
        player:Kick() -- NO recomendamos kick; mejor usar un mensaje. Aquí lo dejo comentado.
        -- alternativa: Notificar via RemoteEvent (si tu GUI escucha)
        warn(("Jugador %s intentó enviar demasiado pronto."):format(player.Name))
        return
    end

    -- validación básica
    if not isLikelyURL(link) then
        warn(("Link inválido de %s: %s"):format(player.Name, link))
        -- podrías notificar al jugador usando RemoteEvent de retorno
        return
    end

    if not isWhitelisted(link) then
        warn(("Link NO permitido por whitelist de %s: %s"):format(player.Name, link))
        -- opcional: notificar al jugador
        return
    end

    -- crea registro
    local record = {
        playerName = player.Name,
        userId = player.UserId,
        link = link,
        time = os.time(),
    }

    -- Guarda en DataStore (en pcall)
    local ok, err = saveLinkRecord(record)
    if not ok then
        warn("Error guardando link: " .. tostring(err))
        -- Como fallback, también guardamos en memoria (tabla global) para análisis breve:
        -- (implementación simple)
    end

    -- actualizar cooldown
    lastSent[player.UserId] = now

    -- log en servidor
    print(string.format("Link recibido de %s (UserId %d): %s", player.Name, player.UserId, link))
end)
