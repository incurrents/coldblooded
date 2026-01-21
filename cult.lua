local SCRIPT_VERSION = '1.0.1'
local effil = require 'effil'
local UPDATE_VERSION_URL = 'https://raw.githubusercontent.com/incurrents/coldblooded/refs/heads/main/version.txt'
local UPDATE_SCRIPT_URL  = 'https://github.com/incurrents/coldblooded/raw/refs/heads/main/cult.lua'

function downloadNewVersion(ver)
    asyncHttpRequest(
        'GET',
        UPDATE_SCRIPT_URL,
        nil,
        function(resp)
            if resp.status_code ~= 200 or not resp.text then
                msg('Ошибка загрузки обновления')
                return
            end

            local path = thisScript().path

            local f = io.open(path, 'w')
            if not f then
                msg('Не удалось открыть файл для записи')
                return
            end

            f:write(resp.text)
            f:close()

            msg('Скрипт обновлён (' .. ver .. ')')
            thisScript():reload()
        end,
        function(err)
            msg('Ошибка загрузки: ' .. tostring(err))
        end
    )
end



function checkScriptUpdate()
    asyncHttpRequest(
        'GET',
        UPDATE_VERSION_URL,
        nil,
        function(resp)
            if resp.status_code ~= 200 or not resp.text then
                msg('Не удалось проверить версию')
                return
            end

            local remote_version = resp.text:match('[%d%.]+')
            if not remote_version then return end

            if remote_version ~= SCRIPT_VERSION then
                msg(string.format('Найдена новая версия: %s', remote_version))
                downloadNewVersion(remote_version)
            elseif remote_version == SCRIPT_VERSION  then
                msg('Версия '..SCRIPT_VERSION..' актуальная')
            end
        end,
        function(err)
            msg('Ошибка запроса версии: ' .. tostring(err))
        end
    )
end

require 'lib.moonloader'
local imgui = require 'mimgui'
local samp = require('lib.samp.events')
local inicfg = require 'inicfg'
local rkeys = {}
local vkeys = require('vkeys')
local mem = require 'memory'
local MAX_PICKUPS = 4096
local stPickupPtr = nil
local PickupPtr = nil
local fonts = renderCreateFont("Comic Sans MS", 9, 5)
local justOpened = true
local lfs = require 'lfs'
--NOPexplosion
writeMemory(0x736A50, 1, 0xC3, false)
--

--DisaFlyingComponent THX GORSKIN
local ffi = require 'ffi'
ffi.fill(ffi.cast(ffi.typeof('void*'), 0x6A85CC), 5, 0x90)
--
--Inf run
mem.setint8(0xB7CEE4, 1)
--

local FL_DIR = getWorkingDirectory() .. "\\config\\cultFriendList\\"

-- ---------- DATA ----------

local fl_last_update = 0
local FL_UPDATE_INTERVAL = 100


local fl_fonts_ready = false
local fl_friends_set = {}
local fl_online = {}
local fl_friends = {}
local fl_font_head, fl_font_list

local fl_main_cfg = inicfg.load({
    main = {
        activeProfile = "default"
    },
    settings = {
        render    = true,
        showID    = true,
        recolor   = false,
        posX      = 20,
        posY      = 420,
        headText  = "Friends",
        headSize  = 11,
        listSize  = 10,
        gapHead   = 13,
        gapList   = 10,
        headFlags = 1,
        listFlags = 1,
        fontName  = "Segoe UI Black"
    },
    colors = {
        head = 0xFFFFFFFF,
        list = 0xFFFFFFFF
    }
}, "!cultFriendList")

inicfg.save(fl_main_cfg, "!cultFriendList")

local fl_profile = fl_main_cfg.main.activeProfile or "default"




-- ---------- PATHS ----------
local function fl_profile_path(name)
    return FL_DIR .. name .. "\\"
end

local function fl_friends_path()
    return fl_profile_path(fl_profile) .. "friends.json"
end

-- ---------- UTILS ----------
local function strip_colors(s)
    return s and s:gsub("{%x%x%x%x%x%x}", "") or ""
end

local function argb_to_f4(argb)
    return {
        bit.band(bit.rshift(argb, 16), 0xFF) / 255,
        bit.band(bit.rshift(argb, 8), 0xFF) / 255,
        bit.band(argb, 0xFF) / 255,
        bit.band(bit.rshift(argb, 24), 0xFF) / 255
    }
end



local function imgui_f4_to_argb(f)
    return bit.bor(
        bit.lshift(math.floor(f[3] * 255), 24),
        bit.lshift(math.floor(f[0] * 255), 16),
        bit.lshift(math.floor(f[1] * 255), 8),
        math.floor(f[2] * 255)
    )
end



-- ---------- FONTS ----------
function fl_rebuild_fonts(force)
    if not isSampAvailable() then return end

    -- если не force и шрифты уже есть — не трогаем
    if fl_fonts_ready and not force then return end

    fl_font_head = renderCreateFont(
        fl_main_cfg.settings.fontName,
        fl_main_cfg.settings.headSize,
        fl_main_cfg.settings.headFlags
    )

    fl_font_list = renderCreateFont(
        fl_main_cfg.settings.fontName,
        fl_main_cfg.settings.listSize,
        fl_main_cfg.settings.listFlags
    )

    fl_fonts_ready = true
end

-- ---------- SAVE / LOAD ----------
local function fl_list_profiles()
    local list = {}
    if not doesDirectoryExist(FL_DIR) then return list end
    for name in lfs.dir(FL_DIR) do
        if name ~= "." and name ~= ".." then
            table.insert(list, name)
        end
    end
    return list
end



function fl_save_profile()
    local dir = fl_profile_path(fl_profile)
    if not doesDirectoryExist(FL_DIR) then createDirectory(FL_DIR) end
    if not doesDirectoryExist(dir) then createDirectory(dir) end

    local f = io.open(fl_friends_path(), "w")
    if f then
        f:write(encodeJson(fl_friends))
        f:close()
    end
end

function fl_load_profile(name)
    fl_profile = name

    fl_main_cfg.main.activeProfile = name
    inicfg.save(fl_main_cfg, "!cultFriendList")

    local dir = fl_profile_path(name)
    if not doesDirectoryExist(dir) then
        createDirectory(dir)
    end

    fl_friends = {}
    local path = fl_friends_path()
    if doesFileExist(path) then
        local f = io.open(path, "r")
        if f then
            fl_friends = decodeJson(f:read("*a")) or {}
            f:close()
        end
    end
end

-- ---------- INIT ----------
fl_load_profile(fl_profile)
fl_save_profile()

-- ---------- ONLINE CHECK ----------
local function fl_rebuild_friends_set()
    fl_friends_set = {}
    for _, name in ipairs(fl_friends) do
        fl_friends_set[strip_colors(name)] = true
    end
end

local function fl_update_online()
    fl_online = {}
    local maxId = sampGetMaxPlayerId(false)

    for id = 0, maxId do
        if sampIsPlayerConnected(id) then
            local nick = sampGetPlayerNickname(id)
            if nick then
                nick = strip_colors(nick)
                if fl_friends_set[nick] then
                    fl_online[#fl_online + 1] = {
                        id = id,
                        nickname = nick
                    }
                end
            end
        end
    end
end
-- ---------- HUD ----------
local fl_dragging, fl_dx, fl_dy = false, 0, 0
-- ===== FriendList ImGui state =====
local fl_render                 = imgui.new.bool(fl_main_cfg.settings.render)
local fl_showID                 = imgui.new.bool(fl_main_cfg.settings.showID)
local fl_recolor                = imgui.new.bool(fl_main_cfg.settings.recolor)

local fl_head_size              = imgui.new.int(fl_main_cfg.settings.headSize)
local fl_list_size              = imgui.new.int(fl_main_cfg.settings.listSize)

local fl_head_flags             = imgui.new.int(fl_main_cfg.settings.headFlags)
local fl_list_flags             = imgui.new.int(fl_main_cfg.settings.listFlags)

local fl_gap_head               = imgui.new.int(fl_main_cfg.settings.gapHead)
local fl_gap_list               = imgui.new.int(fl_main_cfg.settings.gapList)

local fl_new_name               = imgui.new.char[32]()
local fl_font_input             = imgui.new.char[32](fl_main_cfg.settings.fontName)
local fl_new_profile            = imgui.new.char[24]()

local c                         = argb_to_f4(fl_main_cfg.colors.head)
local fl_col_head               = imgui.new.float[4](c[1], c[2], c[3], c[4])

c                               = argb_to_f4(fl_main_cfg.colors.list)
local fl_col_list               = imgui.new.float[4](c[1], c[2], c[3], c[4])


function fl_sync_imgui()
    fl_render[0]     = fl_main_cfg.settings.render
    fl_showID[0]     = fl_main_cfg.settings.showID
    fl_recolor[0]    = fl_main_cfg.settings.recolor

    fl_head_size[0]  = fl_main_cfg.settings.headSize
    fl_list_size[0]  = fl_main_cfg.settings.listSize

    fl_gap_head[0]   = fl_main_cfg.settings.gapHead
    fl_gap_list[0]   = fl_main_cfg.settings.gapList

    fl_head_flags[0] = fl_main_cfg.settings.headFlags
    fl_list_flags[0] = fl_main_cfg.settings.listFlags

    ffi.copy(fl_font_input, fl_main_cfg.settings.fontName or "Arial")

    local ch = argb_to_f4(fl_main_cfg.colors.head)
    fl_col_head[0], fl_col_head[1], fl_col_head[2], fl_col_head[3] =
        ch[1], ch[2], ch[3], ch[4]

    local cl = argb_to_f4(fl_main_cfg.colors.list)
    fl_col_list[0], fl_col_list[1], fl_col_list[2], fl_col_list[3] =
        cl[1], cl[2], cl[3], cl[4]
end

fl_sync_imgui()


function renderFriendList()
    if not fl_main_cfg.settings.render then return end
    if not isSampAvailable() then return end
    if not fl_font_head or not fl_font_list then return end

    local mx, my = getCursorPos()

    if isKeyDown(VK_LBUTTON) and not sampIsCursorActive() then
        if not fl_dragging then
            if mx >= fl_main_cfg.settings.posX and mx <= fl_main_cfg.settings.posX + 180
                and my >= fl_main_cfg.settings.posY and my <= fl_main_cfg.settings.posY + fl_main_cfg.settings.gapHead then
                fl_dragging = true
                fl_dx = mx - fl_main_cfg.settings.posX
                fl_dy = my - fl_main_cfg.settings.posY
            end
        else
            fl_main_cfg.settings.posX = mx - fl_dx
            fl_main_cfg.settings.posY = my - fl_dy
        end
    else
        if fl_dragging then inicfg.save(fl_main_cfg, "!cultFriendList") end
        fl_dragging = false
    end

    local x, y = fl_main_cfg.settings.posX, fl_main_cfg.settings.posY
    local online = fl_online

    renderFontDrawText(fl_font_head, fl_main_cfg.settings.headText, x, y, fl_main_cfg.colors.head)
    y = y + fl_main_cfg.settings.gapHead

    if #online == 0 then
        renderFontDrawText(fl_font_list, "Нет друзей онлайн", x, y, 0xFFAAAAAA)
        return
    end

    for _, p in ipairs(online) do
        local text = p.nickname
        if fl_main_cfg.settings.showID then
            text = text .. " [" .. p.id .. "]"
        end
        renderFontDrawText(fl_font_list, text, x, y, fl_main_cfg.colors.list)
        y = y + fl_main_cfg.settings.gapList
    end
end

-- ================== MAIN ==================

vkeys.getKeysName = function(keys)
    local result = {}
    for _, key in ipairs(keys) do
        local found = false
        for name, code in pairs(vkeys) do
            if code == key then
                local cleanName = name:gsub("^VK_", "")
                table.insert(result, cleanName)
                found = true
                break
            end
        end
        if not found then
            table.insert(result, tostring(key))
        end
    end
    return result
end


local encoding = require 'encoding'
encoding.default = 'CP1251'
local u8 = encoding.UTF8

local config_name = '#cult'
local settings = inicfg.load({
    config = {
        djkey          = "[50]",
        djstatus       = false,
        sbivkey        = "[18, 50]",
        sbivstatus     = false,
        drift          = false,
        driftkey       = "[32]",
        antilomka      = false,
        lsarender      = false,
        fmembers       = false,
        dacs           = false,
        free           = false,
        ddead          = false,
        sbivcarfix     = false,
        colped         = false,
        autoget        = false,
        dmgun          = false,
        deagleaza      = false,
        m4aza          = false,
        rifleaza       = false,
        deaglekey      = "[50]",
        m4key          = "[51]",
        riflekey       = "[52]",
        deagleCount    = 1,
        m4Count        = 1,
        rifleCount     = 1,
        deagleAzacraft = 1,
        deagleAzacount = 1,
        m4Azacraft     = 1,
        m4Azacount     = 1,
        rifleAzacraft  = 1,
        rifleAzacount  = 1,
        usedeagle      = true,
        usem4          = true,
        userifle       = true,
        uselock        = true,
        usewarelock    = true,
        lockkey        = "[76]",
        warelockkey    = "[80]",
    }
}, config_name)
inicfg.save(settings, config_name)
local deagle_count          = imgui.new.int(settings.config.deagleCount)
local rifle_count           = imgui.new.int(settings.config.rifleCount)
local m4_count              = imgui.new.int(settings.config.m4Count)
local deagle_azacraft       = imgui.new.int(settings.config.deagleAzacraft)
local deagle_azacount       = imgui.new.int(settings.config.deagleAzacount)
local m4_azacraft           = imgui.new.int(settings.config.m4Azacraft)
local m4_azacount           = imgui.new.int(settings.config.m4Azacount)
local rifle_azacraft        = imgui.new.int(settings.config.rifleAzacraft)
local rifle_azacount        = imgui.new.int(settings.config.rifleAzacount)
local win_state             = imgui.new.bool(false)
local show_extra_window     = imgui.new.bool(false)
local waiting_for_key       = nil
local key_buffer            = {}
local ddead                 = imgui.new.bool(settings.config.ddead)
local colped                = imgui.new.bool(settings.config.colped)
local sbivcarfix            = imgui.new.bool(settings.config.sbivcarfix)
local deagleaza             = imgui.new.bool(settings.config.deagleaza)
local m4aza                 = imgui.new.bool(settings.config.m4aza)
local rifleaza              = imgui.new.bool(settings.config.rifleaza)
local dmgun                 = imgui.new.bool(settings.config.dmgun)
local autoget               = imgui.new.bool(settings.config.autoget)
local dacs                  = imgui.new.bool(settings.config.dacs)
local free                  = imgui.new.bool(settings.config.free)
local doublejump            = imgui.new.bool(settings.config.djstatus)
local sbiv                  = imgui.new.bool(settings.config.sbivstatus)
local antilomka             = imgui.new.bool(settings.config.antilomka)
local lsarender             = imgui.new.bool(settings.config.lsarender)
local fmembers              = imgui.new.bool(settings.config.fmembers)
local drift                 = imgui.new.bool(settings.config.drift)
local usedeagle             = imgui.new.bool(settings.config.usedeagle)
local usem4                 = imgui.new.bool(settings.config.usem4)
local userifle              = imgui.new.bool(settings.config.userifle)
local uselock               = imgui.new.bool(settings.config.uselock)
local usewarelock           = imgui.new.bool(settings.config.usewarelock)
local selected_lock_key     = { v = decodeJson(settings.config.lockkey) or { 76 } }
local selected_warelock_key = { v = decodeJson(settings.config.warelockkey) or { 87 } }
local selected_deagle_key   = { v = decodeJson(settings.config.deaglekey) or { 50 } }
local selected_m4_key       = { v = decodeJson(settings.config.m4key) or { 51 } }
local selected_rifle_key    = { v = decodeJson(settings.config.riflekey) or { 52 } }
local selected_key          = { v = decodeJson(settings.config.djkey) or { 50 } }
local selected_sbiv_key     = { v = decodeJson(settings.config.sbivkey) or { 18, 50 } }
local selected_drift_key    = { v = decodeJson(settings.config.driftkey) or { 32 } }
local flsa                  = false



function isComboPressed(keys)
    if type(keys) ~= 'table' then return false end
    if #keys == 1 then
        return isKeyJustPressed(keys[1])
    elseif #keys == 2 then
        return isKeyDown(keys[1]) and isKeyJustPressed(keys[2])
    end
    return false
end

function isComboHeld(keys)
    if type(keys) ~= 'table' then return false end
    if #keys == 1 then
        return isKeyDown(keys[1])
    elseif #keys == 2 then
        return isKeyDown(keys[1]) and isKeyDown(keys[2])
    end
    return false
end

function formatCombo(keys)
    local names = {}
    for _, k in ipairs(keys) do
        table.insert(names, vkeys.getKeysName({ k })[1] or '?')
    end
    return table.concat(names, " + ")
end

function main()
    while not isSampAvailable() do wait(100) end
    while not stPickupPtr do
        stPickupPtr = sampGetPickupPoolPtr()
        PickupPtr = stPickupPtr
        wait(100)
    end
    stPickupPtr = stPickupPtr + 0xF004
    fl_rebuild_friends_set()
    fl_update_online()
    fl_rebuild_fonts()
    msg('Загружен! открыть меню /cult')
    sampRegisterChatCommand('cult', function()
        win_state[0] = not win_state[0]
        if win_state[0] then
            justOpened = true
        end
    end)
    sampRegisterChatCommand('flsa', function()
        flsa = not flsa
        msg(flsa and 'FLSA Включен!' or 'FLSA Выключен!')
    end)
    checkScriptUpdate()
    while true do
        wait(0)
        local now = os.clock() * 1000
        if now - fl_last_update > FL_UPDATE_INTERVAL then
            fl_update_online()
            fl_last_update = now
        end
        renderFriendList()

        if flsa then
            local pickupIndex = nil
            for i = 0, MAX_PICKUPS - 1 do
                local base = stPickupPtr + i * 20

                local handle = mem.getuint32(base + 0x04)
                if handle and handle ~= 0 then
                    local px = mem.getfloat(base + 0x08)
                    local py = mem.getfloat(base + 0x0C)
                    local pz = mem.getfloat(base + 0x10)

                    local mx, my, mz = getCharCoordinates(PLAYER_PED)
                    local dist = getDistanceBetweenCoords3d(px, py, pz, mx, my, mz)

                    local modelId = mem.read(base, 4)

                    if dist < 15 and not isCharInAnyCar(PLAYER_PED) and modelId == 2358 then
                        pickupIndex = i
                    elseif dist < 15 and not isCharInAnyCar(PLAYER_PED) and modelId == 353 then
                        pickupIndex = i
                    end
                end
            end

            if pickupIndex then
                sampSendPickedUpPickup(pickupIndex)
                sampSendChat('/materials put')
                wait(1100)
            else
                msg('Не нашел пикап')
                flsa = false
            end
        end



        if waiting_for_key and not sampIsCursorActive() then
            local mainKey = nil
            local holdKey = nil

            for i = 1, 255 do
                if isKeyJustPressed(i) then
                    mainKey = i
                    break
                end
            end

            if mainKey then
                for i = 1, 255 do
                    if i ~= mainKey and isKeyDown(i) then
                        holdKey = i
                        break
                    end
                end

                local combo = holdKey and { holdKey, mainKey } or { mainKey }

                if waiting_for_key == 'dj' then
                    selected_key.v = combo
                    settings.config.djkey = encodeJson(combo)
                elseif waiting_for_key == 'sbiv' then
                    selected_sbiv_key.v = combo
                    settings.config.sbivkey = encodeJson(combo)
                elseif waiting_for_key == 'deagle' then
                    selected_deagle_key.v = combo
                    settings.config.deaglekey = encodeJson(combo)
                elseif waiting_for_key == 'm4' then
                    selected_m4_key.v = combo
                    settings.config.m4key = encodeJson(combo)
                elseif waiting_for_key == 'rifle' then
                    selected_rifle_key.v = combo
                    settings.config.riflekey = encodeJson(combo)
                elseif waiting_for_key == 'drift' then
                    selected_drift_key.v = combo
                    settings.config.driftkey = encodeJson(combo)
                elseif waiting_for_key == 'lock' then
                    selected_lock_key.v = combo
                    settings.config.lockkey = encodeJson(combo)
                elseif waiting_for_key == 'warelock' then
                    selected_warelock_key.v = combo
                    settings.config.warelockkey = encodeJson(combo)
                end

                inicfg.save(settings, config_name)
                waiting_for_key = nil
            end
        end

        local collisionState = {}

        if colped[0] then
            local px, py, pz = getCharCoordinates(playerPed)
            local maxId = sampGetMaxPlayerId(false)

            for playerId = 0, maxId do
                if sampIsPlayerConnected(playerId) then
                    local ok, ped = sampGetCharHandleBySampPlayerId(playerId)

                    if ok and doesCharExist(ped) and not isCharInAnyCar(ped) and ped ~= playerPed then
                        local x, y, z = getCharCoordinates(ped)
                        local near = getDistanceBetweenCoords3d(px, py, pz, x, y, z) <= 1

                        if collisionState[ped] ~= near then
                            collisionState[ped] = near
                            setCharCollision(ped, not near)
                        end
                    end
                end
            end
        end

        if drift[0] then
            if isCharInAnyCar(playerPed) then
                local car = storeCarCharIsInNoSave(playerPed)
                local speed = getCarSpeed(car)
                isCarInAirProper(car)
                setCarCollision(car, true)
                if isComboHeld(selected_drift_key.v) and isVehicleOnAllWheels(car) and doesVehicleExist(car) and speed > 5.0 then
                    setCarCollision(car, false)
                    if isCarInAirProper(car) then
                        setCarCollision(car, true)
                        if isKeyDown(VK_A)
                        then
                            addToCarRotationVelocity(car, 0, 0, 0.15)
                        end
                        if isKeyDown(VK_D)
                        then
                            addToCarRotationVelocity(car, 0, 0, -0.15)
                        end
                    end
                end
            end
        end
        if lsarender[0] then
            for id = 0, 2048 do
                local result = sampIs3dTextDefined(id)
                if result then
                    local text, color, posx, posy, posz, distance, ignoreWalls, playerId, vehicleId =
                        sampGet3dTextInfoById(id)
                    if text:find('{.+}Боеприпасы: %d+') then
                        local materials = text:match('{.+}Боеприпасы: (%d+)')
                        local vx, vy = convert3DCoordsToScreen(posx, posy, posz)
                        local x, y, z = getCharCoordinates(PLAYER_PED)
                        local px, py = convert3DCoordsToScreen(x, y, z)
                        local resX, resY = getScreenResolution()
                        if vx < resX and vy < resY and isPointOnScreen(posx, posy, posz, 1) then
                            renderFontDrawText(fonts, '{c0c0c0}Материалы:{3E8FBF} ' .. materials, vx, vy, -1)
                        end
                    end
                end
            end
        end

        if deagleaza[0] then
            local ammo = getAmmoInCharWeapon(PLAYER_PED, 24)
            if ammo == deagle_azacraft[0] then
                sampSendChat('/de ' .. tostring(deagle_azacount[0]))
                wait(1000)
            end
        end
        if m4aza[0] then
            local ammo = getAmmoInCharWeapon(PLAYER_PED, 31)
            if ammo == m4_azacraft[0] then
                sampSendChat('/m4 ' .. tostring(m4_azacount[0]))
                wait(1000)
            end
        end
        if rifleaza[0] then
            local ammo = getAmmoInCharWeapon(PLAYER_PED, 33)
            if ammo == rifle_azacraft[0] then
                sampSendChat('/ri ' .. tostring(rifle_azacount[0]))
                wait(1000)
            end
        end


        if dmgun[0] then
            removeWeaponFromChar(PLAYER_PED, 1)
            removeWeaponFromChar(PLAYER_PED, 2)
            removeWeaponFromChar(PLAYER_PED, 5)
            removeWeaponFromChar(PLAYER_PED, 6)
            removeWeaponFromChar(PLAYER_PED, 7)
            removeWeaponFromChar(PLAYER_PED, 8)
        end

        if usedeagle[0] and isComboPressed(selected_deagle_key.v) and not sampIsCursorActive() then
            sampSendChat("/de " .. tostring(deagle_count[0]))
        end

        if usem4[0] and isComboPressed(selected_m4_key.v) and not sampIsCursorActive() then
            sampSendChat("/m4 " .. tostring(m4_count[0]))
        end

        if userifle[0] and isComboPressed(selected_rifle_key.v) and not sampIsCursorActive() then
            sampSendChat("/rifle " .. tostring(rifle_count[0]))
        end

        if uselock[0] and isComboPressed(selected_lock_key.v) and not sampIsCursorActive() then
            sampSendChat('/lock')
        end

        if usewarelock[0] and isComboPressed(selected_warelock_key.v) and not sampIsCursorActive() then
            sampSendChat('/warelock')
        end

        if doublejump[0] and isComboPressed(selected_key.v) and not sampIsCursorActive() then
            taskPlayAnimNonInterruptable(PLAYER_PED, "colt45_reload", "COLT45", 4.1, false, false, true, true, 1)
            wait(1)
            for a = 1, 12 do
                if a == 3 then
                    taskPlayAnimNonInterruptable(PLAYER_PED, "colt45_reload", "COLT45", 4.1, false, false, true, true, 1)
                end
                setVirtualKeyDown(VK_LSHIFT, true)
                wait(1)
                setVirtualKeyDown(VK_LSHIFT, false)
                wait(1)
            end
        end

        if sbiv[0] and isComboPressed(selected_sbiv_key.v) and not sampIsCursorActive() then
            if isCharInAnyCar(PLAYER_PED) then
                local carHandle = storeCarCharIsInNoSave(PLAYER_PED)
                local result, carId = sampGetVehicleIdByCarHandle(carHandle)
                if result then
                    sampSendExitVehicle(carId)
                    local carX, carY, carZ = getCarCoordinates(carHandle)
                    local model = getCarModel(carHandle)
                    local zOffset = 1.0
                    if model == 487 or model == 469 or model == 447 or model == 425 or model == 548 or model == 417 then
                        zOffset = -3
                    end
                    warpCharFromCarToCoord(PLAYER_PED, carX, carY, carZ + zOffset)
                end
            else
                setPlayerControl(PLAYER_HANDLE, true)
                freezeCharPosition(PLAYER_PED, false)
                clearCharTasksImmediately(PLAYER_PED)
            end
        end
    end
end

local function drawMainTab()
    if imgui.Checkbox(u8 "Удалять аксессуары", dacs) then
        settings.config.dacs = dacs[0]
        inicfg.save(settings, config_name)
    end
    imgui.SameLine(0, 4)
    imgui.TextDisabled('?')
    imgui.Hint('hintdacs', u8 'Удаляет аксессуары на себе и на других')
    imgui.SameLine(nil, 70) -- сдвиг вправо, можно подрегулировать
    imgui.TextDisabled(u8 "Доп Функции")
    if imgui.IsItemHovered() then
        imgui.SetTooltip(u8 "Нажмите, чтобы открыть окно")
    end
    if imgui.IsItemClicked() then
        show_extra_window[0] = not show_extra_window[0]
    end
    if imgui.Checkbox(u8 "Убрать колизию у игроков", colped) then
        settings.config.colped = colped[0]
        inicfg.save(settings, config_name)
    end
    imgui.SameLine(0, 4)
    imgui.TextDisabled('?')
    imgui.Hint('hintcolped', u8 'Убирает колизию у игроков')

    if imgui.Checkbox(u8 "Клисты в /fmembers", fmembers) then
        settings.config.fmembers = fmembers[0]
        inicfg.save(settings, config_name)
    end
    imgui.SameLine(0, 4)
    imgui.TextDisabled('?')
    imgui.Hint('hintfmembers', u8 'Показывает клисты игроков в /fmembers')

    if imgui.Checkbox(u8 "Удалять трупы", ddead) then
        settings.config.ddead = ddead[0]
        inicfg.save(settings, config_name)
    end
    imgui.SameLine(0, 4)
    imgui.TextDisabled('?')
    imgui.Hint('hintddead', u8 'Удаляет трупы игроков')

    if imgui.Checkbox(u8 "ДаблДжамп", doublejump) then
        settings.config.djstatus = doublejump[0]
        inicfg.save(settings, config_name)
    end

    local dj_key_name = formatCombo(selected_key.v)
    local dj_btn_label = (waiting_for_key == 'dj') and u8 "Нажмите клавиши..." or u8(dj_key_name)
    if imgui.Button(dj_btn_label, imgui.ImVec2(100, 0)) then
        waiting_for_key = 'dj'
        key_buffer = {}
    end
    imgui.SameLine()
    imgui.Text(u8 "Бинд ДаблДжампа")
    imgui.SameLine(0, 4)
    imgui.TextDisabled('?')
    imgui.Hint('hintdj',
        u8 'Чтобы забиндить две кнопки сразу надо их сперва зажать и потом нажать на выбор кнопки')
    if imgui.Checkbox(u8 "Сбив", sbiv) then
        settings.config.sbivstatus = sbiv[0]
        inicfg.save(settings, config_name)
    end
    imgui.SameLine(0, 4)
    imgui.TextDisabled('?')
    imgui.Hint('hintsbiv', u8 'Сбив на кнопку, также выкидывает из транспорта на кнопку')

    local sbiv_key_name = formatCombo(selected_sbiv_key.v)
    local sbiv_btn_label = (waiting_for_key == 'sbiv') and u8 "Нажмите клавиши..." or u8(sbiv_key_name)
    if imgui.Button(sbiv_btn_label, imgui.ImVec2(100, 0)) then
        waiting_for_key = 'sbiv'
        key_buffer = {}
    end
    imgui.SameLine()
    imgui.Text(u8 "Бинд Сбива")
    imgui.SameLine(0, 4)
    imgui.TextDisabled('?')
    imgui.Hint('hintsbivv',
        u8 'Чтобы забиндить две кнопки сразу надо их сперва зажать и потом нажать на выбор кнопки')

    if imgui.Checkbox(u8 "Автовзятие Материалов", autoget) then
        settings.config.autoget = autoget[0]
        inicfg.save(settings, config_name)
    end
    imgui.SameLine(0, 4)
    imgui.TextDisabled('?')
    imgui.Hint('hintautoget', u8 'Автоматически берет материалы при открытии склада')

    if imgui.Checkbox(u8 "Удаление холодного оружия", dmgun) then
        settings.config.dmgun = dmgun[0]
        inicfg.save(settings, config_name)
    end
    imgui.SameLine(0, 4)
    imgui.TextDisabled('?')
    imgui.Hint('hintdmgun', u8 'Удаляет холодное оружие по типу биты, кия и т.д')

    if imgui.Checkbox(u8 "Дрифт", drift) then
        settings.config.drift = drift[0]
        inicfg.save(settings, config_name)
    end

    local drift_key_name = formatCombo(selected_drift_key.v)
    local drift_btn_label = (waiting_for_key == 'drift') and u8 "Нажмите клавиши..." or u8(drift_key_name)

    if imgui.Button(drift_btn_label, imgui.ImVec2(100, 0)) then
        waiting_for_key = 'drift'
        key_buffer = {}
    end
    imgui.SameLine()
    imgui.Text(u8 "Бинд Дрифта")
    imgui.SameLine(0, 4)
    imgui.TextDisabled('?')
    imgui.Hint('hintdrift', u8 'Чтобы забиндить две кнопки сразу надо их сперва зажать и потом нажать на выбор кнопки')
    if imgui.Checkbox(u8 "Фикс сбива падения из тачки", sbivcarfix) then
        settings.config.sbivcarfix = sbivcarfix[0]
        inicfg.save(settings, config_name)
    end
    imgui.SameLine(0, 4)
    imgui.TextDisabled('?')
    imgui.Hint('hintsbivcarfix',
        u8 'Убирает анимацию падения у игроков когда они вылетают из нее и сбивают эту анимку (КРАШИТ С PRMENU).')

    if imgui.Checkbox(u8 "Анти Ломка", antilomka) then
        settings.config.antilomka = antilomka[0]
        inicfg.save(settings, config_name)
    end
    imgui.SameLine(0, 4)
    imgui.TextDisabled('?')
    imgui.Hint('hintantilomka', u8 'Убирает анимацию ломки')

    if imgui.Checkbox(u8 "Рендер Материалов на лса", lsarender) then
        settings.config.lsarender = lsarender[0]
        inicfg.save(settings, config_name)
    end
    imgui.SameLine(0, 4)
    imgui.TextDisabled('?')
    imgui.Hint('hintlsaa', u8 'Рисует сколько материалов в ангаре из далека')
    imgui.TextDisabled(u8 "VK Автора")
    if imgui.IsItemHovered() then
        imgui.Hint('hintavtor', u8 'Нажмите чтобы открыть')
    end
    if imgui.IsItemClicked() then
        os.execute("start \"\" \"https://vk.com/prof1it\"")
    end
    imgui.SameLine(0, 4)
    imgui.TextDisabled(u8 "VK Состава")
    imgui.Hint('hintsostav', u8 'Нажмите чтобы открыть')
    if imgui.IsItemClicked() then
        os.execute("start \"\" \"https://vk.com/coldblooded.cult\"")
    end
end

local function drawBindTab()
    -- ===== Deagle =====
    if imgui.Checkbox(u8 "Активировать бинд Deagle", usedeagle) then
        settings.config.usedeagle = usedeagle[0]
        inicfg.save(settings, config_name)
    end
    local deagle_name = formatCombo(selected_deagle_key.v)
    local deagle_btn  = (waiting_for_key == 'deagle') and u8 "Нажмите..." or u8(deagle_name)
    if imgui.Button(deagle_btn, imgui.ImVec2(100, 0)) then
        waiting_for_key = 'deagle'
        key_buffer = {}
    end
    imgui.SameLine()
    imgui.Text(u8 "Бинд Deagle")
    imgui.SameLine(0, 4)
    imgui.TextDisabled('?')
    imgui.Hint('hintdeagle', u8 'Чтобы забиндить две кнопки сразу надо их сперва зажать и потом нажать на выбор кнопки')
    imgui.Text(u8 "Количество Deagle для крафта")
    if imgui.SliderInt("##decount", deagle_count, 1, 100) then
        settings.config.deagleCount = deagle_count[0]
        inicfg.save(settings, config_name)
    end

    imgui.Separator()

    -- ===== M4 =====
    if imgui.Checkbox(u8 "Активировать бинд M4", usem4) then
        settings.config.usem4 = usem4[0]
        inicfg.save(settings, config_name)
    end
    local m4_name = formatCombo(selected_m4_key.v)
    local m4_btn  = (waiting_for_key == 'm4') and u8 "Нажмите..." or u8(m4_name)
    if imgui.Button(m4_btn, imgui.ImVec2(100, 0)) then
        waiting_for_key = 'm4'
        key_buffer = {}
    end
    imgui.SameLine()
    imgui.Text(u8 "Бинд M4")
    imgui.SameLine(0, 4)
    imgui.TextDisabled('?')
    imgui.Hint('hintm4', u8 'Чтобы забиндить две кнопки сразу надо их сперва зажать и потом нажать на выбор кнопки')
    imgui.Text(u8 "Количество M4 для крафта")
    if imgui.SliderInt("##m4count", m4_count, 1, 100) then
        settings.config.m4Count = m4_count[0]
        inicfg.save(settings, config_name)
    end

    imgui.Separator()

    -- ===== Rifle =====
    if imgui.Checkbox(u8 "Активировать бинд Rifle", userifle) then
        settings.config.userifle = userifle[0]
        inicfg.save(settings, config_name)
    end
    local rifle_name = formatCombo(selected_rifle_key.v)
    local rifle_btn  = (waiting_for_key == 'rifle') and u8 "Нажмите..." or u8(rifle_name)
    if imgui.Button(rifle_btn, imgui.ImVec2(100, 0)) then
        waiting_for_key = 'rifle'
        key_buffer = {}
    end
    imgui.SameLine()
    imgui.Text(u8 "Бинд Rifle")
    imgui.SameLine(0, 4)
    imgui.TextDisabled('?')
    imgui.Hint('hintrifle', u8 'Чтобы забиндить две кнопки сразу надо их сперва зажать и потом нажать на выбор кнопки')
    imgui.Text(u8 "Количество Rifle для крафта")
    if imgui.SliderInt("##riflecount", rifle_count, 1, 100) then
        settings.config.rifleCount = rifle_count[0]
        inicfg.save(settings, config_name)
    end

    imgui.Separator()

    -- ===== /lock =====
    if imgui.Checkbox(u8 "Активировать бинд /lock", uselock) then
        settings.config.uselock = uselock[0]
        inicfg.save(settings, config_name)
    end
    local lock_name = formatCombo(selected_lock_key.v)
    local lock_btn  = (waiting_for_key == 'lock') and u8 "Нажмите..." or u8(lock_name)
    if imgui.Button(lock_btn, imgui.ImVec2(100, 0)) then
        waiting_for_key = 'lock'
        key_buffer = {}
    end
    imgui.SameLine()
    imgui.Text(u8 "Бинд /lock")
    imgui.SameLine(0, 4)
    imgui.TextDisabled('?')
    imgui.Hint('hintlock', u8 'Чтобы забиндить две кнопки сразу надо их сперва зажать и потом нажать на выбор кнопки')
    imgui.Separator()

    -- ===== /warelock =====
    if imgui.Checkbox(u8 "Активировать бинд /warelock", usewarelock) then
        settings.config.usewarelock = usewarelock[0]
        inicfg.save(settings, config_name)
    end
    local warelock_name = formatCombo(selected_warelock_key.v)
    local warelock_btn  = (waiting_for_key == 'warelock') and u8 "Нажмите..." or u8(warelock_name)
    if imgui.Button(warelock_btn, imgui.ImVec2(100, 0)) then
        waiting_for_key = 'warelock'
        key_buffer = {}
    end
    imgui.SameLine()
    imgui.Text(u8 "Бинд /warelock")
    imgui.SameLine(0, 4)
    imgui.TextDisabled('?')
    imgui.Hint('hintwarelock', u8 'Чтобы забиндить две кнопки сразу надо их сперва зажать и потом нажать на выбор кнопки')
    imgui.TextDisabled('ver '..SCRIPT_VERSION)
end



local function drawAmmoTab()
    if imgui.Checkbox(u8 "AntiZeroAmmo на Deagle", deagleaza) then
        settings.config.deagleaza = deagleaza[0]
        inicfg.save(settings, config_name)
    end
    imgui.Text(u8 "Кол-во патрон Deagle при котором будет крафтить")
    imgui.SameLine()
    if imgui.SliderInt("##detocraft", deagle_azacraft, 1, 100) then
        settings.config.deagleAzacraft = deagle_azacraft[0]
        inicfg.save(settings, config_name)
    end
    imgui.Text(u8 "Кол-во сколько будет крафтить Deagle")
    imgui.SameLine()
    if imgui.SliderInt("##deazacount", deagle_azacount, 1, 100) then
        settings.config.deagleAzacount = deagle_azacount[0]
        inicfg.save(settings, config_name)
    end

    if imgui.Checkbox(u8 "AntiZeroAmmo на M4", m4aza) then
        settings.config.m4aza = m4aza[0]
        inicfg.save(settings, config_name)
    end
    imgui.Text(u8 "Кол-во патрон M4 при котором будет крафтить")
    imgui.SameLine()
    if imgui.SliderInt("##m4tocraft", m4_azacraft, 1, 100) then
        settings.config.m4Azacraft = m4_azacraft[0]
        inicfg.save(settings, config_name)
    end
    imgui.Text(u8 "Кол-во сколько будет крафтить M4")
    imgui.SameLine()
    if imgui.SliderInt("##m4azacount", m4_azacount, 1, 100) then
        settings.config.m4Azacount = m4_azacount[0]
        inicfg.save(settings, config_name)
    end

    if imgui.Checkbox(u8 "AntiZeroAmmo на Rifle", rifleaza) then
        settings.config.rifleaza = rifleaza[0]
        inicfg.save(settings, config_name)
    end
    imgui.Text(u8 "Кол-во патрон Rifle при котором будет крафтить")
    imgui.SameLine()
    if imgui.SliderInt("##rifletocraft", rifle_azacraft, 1, 100) then
        settings.config.rifleAzacraft = rifle_azacraft[0]
        inicfg.save(settings, config_name)
    end
    imgui.Text(u8 "Кол-во сколько будет крафтить Rifle")
    imgui.SameLine()
    if imgui.SliderInt("##rifleazacount", rifle_azacount, 1, 100) then
        settings.config.rifleAzacount = rifle_azacount[0]
        inicfg.save(settings, config_name)
    end
    imgui.TextDisabled('ver '..SCRIPT_VERSION)
end

local function drawFriendListTab()
    if imgui.Checkbox(u8 "Включить HUD", fl_render) then
        fl_main_cfg.settings.render = fl_render[0]
        inicfg.save(fl_main_cfg, "!cultFriendList")
    end
    if imgui.Checkbox(u8 "Показывать ID", fl_showID) then
        fl_main_cfg.settings.showID = fl_showID[0]
        inicfg.save(fl_main_cfg, "!cultFriendList")
    end
    imgui.Text(u8 "Профиль:")

    local profiles = fl_list_profiles()
    for _, name in ipairs(profiles) do
        local selected = (fl_profile == name)
        if imgui.Selectable(u8(name) .. "##profile_" .. name, selected) then
            fl_load_profile(name)
            fl_rebuild_friends_set()
            fl_update_online()
            fl_sync_imgui()
        end
    end



    imgui.InputText("##new_profile", fl_new_profile, 24)
    imgui.SameLine()
    if imgui.Button(u8 "Создать профиль") then
        local name = ffi.string(fl_new_profile)
        name = name:gsub("^%s+", ""):gsub("%s+$", "")

        if #name > 0 then
            fl_load_profile(name)                       -- загрузили / создали профиль
            fl_save_profile()                           -- сохранили friends.json
            inicfg.save(fl_main_cfg, "!cultFriendList") -- сохранили activeProfile
            ffi.fill(fl_new_profile, 24)
        end
    end


    imgui.Text(u8 "Добавить ник:")

    imgui.InputText("##fl_add", fl_new_name, 32)
    imgui.SameLine()

    if imgui.Button(u8 "Добавить") then
        local name = ffi.string(fl_new_name)
        name = name:gsub("^%s+", ""):gsub("%s+$", "")

        if #name > 0 then
            local exists = false
            for _, n in ipairs(fl_friends) do
                if n == name then
                    exists = true
                    break
                end
            end

            if not exists then
                table.insert(fl_friends, name)
                fl_rebuild_friends_set()
                fl_update_online()
                fl_save_profile()
            end
        end

        ffi.fill(fl_new_name, 32)
    end

    imgui.Text(u8 "Шрифт:")

    imgui.InputText("##fl_font", fl_font_input, 32)
    imgui.SameLine()

    if imgui.Button(u8 "Применить") then
        fl_main_cfg.settings.fontName = ffi.string(fl_font_input)
        inicfg.save(fl_main_cfg, "!cultFriendList")
        fl_rebuild_fonts(true)
    end

    imgui.Text(u8 "Цвета:")

    if imgui.ColorEdit4(u8 "Заголовок", fl_col_head) then
        fl_main_cfg.colors.head = imgui_f4_to_argb(fl_col_head)
        inicfg.save(fl_main_cfg, "!cultFriendList")
    end

    if imgui.ColorEdit4(u8 "Список", fl_col_list) then
        fl_main_cfg.colors.list = imgui_f4_to_argb(fl_col_list)
        inicfg.save(fl_main_cfg, "!cultFriendList")
    end
    imgui.Text(u8 "Размеры текста:")

    imgui.Text(u8 "Заголовок")
    if imgui.SliderInt("##fl_head_size", fl_head_size, 8, 32) then
        fl_main_cfg.settings.headSize = fl_head_size[0]
        inicfg.save(fl_main_cfg, "!cultFriendList")
        fl_rebuild_fonts(true)
    end

    imgui.Text(u8 "Список")
    if imgui.SliderInt("##fl_list_size", fl_list_size, 8, 24) then
        fl_main_cfg.settings.listSize = fl_list_size[0]
        inicfg.save(fl_main_cfg, "!cultFriendList")
        fl_rebuild_fonts(true)
    end
    imgui.Text(u8 "Отступы:")

    imgui.Text(u8 "Заголовок")
    if imgui.SliderInt("##fl_gap_head", fl_gap_head, 0, 50) then
        fl_main_cfg.settings.gapHead = fl_gap_head[0]
        inicfg.save(fl_main_cfg, "!cultFriendList")
    end

    imgui.Text(u8 "Между никами")
    if imgui.SliderInt("##fl_gap_list", fl_gap_list, 0, 30) then
        fl_main_cfg.settings.gapList = fl_gap_list[0]
        inicfg.save(fl_main_cfg, "!cultFriendList")
    end
    imgui.Text(u8 "Флаги шрифта")
    if imgui.SliderInt(u8 "Флаги заголовка", fl_head_flags, 0, 15) then
        fl_main_cfg.settings.headFlags = fl_head_flags[0]
        inicfg.save(fl_main_cfg, "!cultFriendList")
        fl_rebuild_fonts(true)
    end

    if imgui.SliderInt(u8 "Флаги списка", fl_list_flags, 0, 15) then
        fl_main_cfg.settings.listFlags = fl_list_flags[0]
        inicfg.save(fl_main_cfg, "!cultFriendList")
        fl_rebuild_fonts(true)
    end
    imgui.Text(u8 "Друзья:")

    if #fl_friends == 0 then
        imgui.TextDisabled(u8 "Список пуст")
    end

    for i, name in ipairs(fl_friends) do
        imgui.BulletText(name)
        imgui.SameLine()
        if imgui.SmallButton("X##fl" .. i) then
            table.remove(fl_friends, i)
            fl_rebuild_friends_set()
            fl_update_online()
            fl_save_profile()
        end
    end
end



local current_tab = 1
local tab_names = { "Основное", "Бинды", "AntiZeroAmmo", "FriendList" }
imgui.OnFrame(function() return win_state[0] end, function()
    if justOpened then
        local screenX, screenY = getScreenResolution()
        imgui.SetNextWindowPos(
            imgui.ImVec2(screenX / 2, screenY / 2),
            imgui.Cond.Always,
            imgui.ImVec2(0.5, 0.5)
        )
        justOpened = false
    end
    local tab_size = imgui.ImVec2(110, 0)
    local total_tab_width = (#tab_names * tab_size.x) + ((#tab_names - 1) * 6) -- кнопки + SameLine spacing

    if current_tab == 1 then
        imgui.SetNextWindowSize(imgui.ImVec2(325, 478), imgui.Cond.Always)
    elseif current_tab == 2 then
        imgui.SetNextWindowSize(imgui.ImVec2(325, 510), imgui.Cond.Always)
    elseif current_tab == 3 then
        imgui.SetNextWindowSize(imgui.ImVec2(565, 320), imgui.Cond.Always)
    elseif current_tab == 4 then
        imgui.SetNextWindowSize(imgui.ImVec2(385, 590), imgui.Cond.Always)
    end
    imgui.Begin(u8 "COLDBLOODED CULT", win_state,
        imgui.WindowFlags.AlwaysAutoResize + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoCollapse)
    for i, name in ipairs(tab_names) do
        if i > 1 then imgui.SameLine() end
        if current_tab == i then
            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.2, 0.6, 1.0, 1.0)) -- активная вкладка
        else
            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.2, 0.2, 0.2, 1.0)) -- неактивная
        end

        if imgui.Button(u8(name)) then
            current_tab = i
        end
        imgui.PopStyleColor()
    end

    imgui.Separator()

    -- Отображаем содержимое вкладки
    if current_tab == 1 then
        drawMainTab()
    elseif current_tab == 2 then
        drawBindTab()
    elseif current_tab == 3 then
        drawAmmoTab()
    elseif current_tab == 4 then
        drawFriendListTab()
    end
    local style                             = imgui.GetStyle()
    local colors                            = style.Colors
    style.Alpha                             = 1.0
    style.WindowPadding                     = imgui.ImVec2(10, 10)
    style.WindowRounding                    = 6.0
    style.FramePadding                      = imgui.ImVec2(5, 3)
    style.FrameRounding                     = 4.0
    style.ItemSpacing                       = imgui.ImVec2(8, 6)
    style.ItemInnerSpacing                  = imgui.ImVec2(5, 5)
    style.IndentSpacing                     = 20.0
    style.ScrollbarSize                     = 15.0
    style.ScrollbarRounding                 = 9.0
    style.GrabMinSize                       = 10.0
    style.GrabRounding                      = 4.0
    style.WindowBorderSize                  = 0.0
    style.FrameBorderSize                   = 0.0
    style.WindowTitleAlign                  = imgui.ImVec2(0.5, 0.5)

    colors[imgui.Col.Text]                  = imgui.ImVec4(0.80, 0.90, 1.00, 1.00)
    colors[imgui.Col.TextDisabled]          = imgui.ImVec4(0.50, 0.60, 0.70, 1.00)
    colors[imgui.Col.WindowBg]              = imgui.ImVec4(0.05, 0.08, 0.15, 0.94)
    colors[imgui.Col.ChildBg]               = imgui.ImVec4(0.07, 0.10, 0.17, 0.94)
    colors[imgui.Col.PopupBg]               = imgui.ImVec4(0.10, 0.12, 0.20, 0.94)
    colors[imgui.Col.Border]                = imgui.ImVec4(0.40, 0.50, 0.60, 0.40)
    colors[imgui.Col.BorderShadow]          = imgui.ImVec4(0.00, 0.00, 0.00, 0.00)
    colors[imgui.Col.FrameBg]               = imgui.ImVec4(0.10, 0.13, 0.22, 0.60)
    colors[imgui.Col.FrameBgHovered]        = imgui.ImVec4(0.25, 0.40, 0.60, 0.65)
    colors[imgui.Col.FrameBgActive]         = imgui.ImVec4(0.30, 0.50, 0.70, 0.70)
    colors[imgui.Col.TitleBg]               = imgui.ImVec4(0.04, 0.06, 0.10, 1.00)
    colors[imgui.Col.TitleBgActive]         = imgui.ImVec4(0.08, 0.12, 0.18, 1.00)
    colors[imgui.Col.TitleBgCollapsed]      = imgui.ImVec4(0.00, 0.00, 0.00, 0.60)
    colors[imgui.Col.MenuBarBg]             = imgui.ImVec4(0.07, 0.10, 0.15, 1.00)
    colors[imgui.Col.ScrollbarBg]           = imgui.ImVec4(0.02, 0.04, 0.07, 0.50)
    colors[imgui.Col.ScrollbarGrab]         = imgui.ImVec4(0.30, 0.50, 0.70, 0.60)
    colors[imgui.Col.ScrollbarGrabHovered]  = imgui.ImVec4(0.35, 0.60, 0.85, 0.80)
    colors[imgui.Col.ScrollbarGrabActive]   = imgui.ImVec4(0.40, 0.70, 0.95, 1.00)
    colors[imgui.Col.CheckMark]             = imgui.ImVec4(0.60, 0.90, 1.00, 1.00)
    colors[imgui.Col.SliderGrab]            = imgui.ImVec4(0.60, 0.80, 1.00, 0.60)
    colors[imgui.Col.SliderGrabActive]      = imgui.ImVec4(0.70, 0.90, 1.00, 0.80)
    colors[imgui.Col.Button]                = imgui.ImVec4(0.10, 0.20, 0.30, 0.60)
    colors[imgui.Col.ButtonHovered]         = imgui.ImVec4(0.20, 0.35, 0.50, 0.85)
    colors[imgui.Col.ButtonActive]          = imgui.ImVec4(0.30, 0.55, 0.75, 1.00)
    colors[imgui.Col.Header]                = imgui.ImVec4(0.20, 0.40, 0.60, 0.45)
    colors[imgui.Col.HeaderHovered]         = imgui.ImVec4(0.30, 0.55, 0.80, 0.80)
    colors[imgui.Col.HeaderActive]          = imgui.ImVec4(0.40, 0.70, 1.00, 1.00)
    colors[imgui.Col.Separator]             = imgui.ImVec4(0.35, 0.50, 0.70, 0.60)
    colors[imgui.Col.SeparatorHovered]      = imgui.ImVec4(0.40, 0.65, 1.00, 0.80)
    colors[imgui.Col.SeparatorActive]       = imgui.ImVec4(0.50, 0.80, 1.00, 1.00)
    colors[imgui.Col.ResizeGrip]            = imgui.ImVec4(0.20, 0.40, 0.60, 0.30)
    colors[imgui.Col.ResizeGripHovered]     = imgui.ImVec4(0.35, 0.55, 0.80, 0.70)
    colors[imgui.Col.ResizeGripActive]      = imgui.ImVec4(0.50, 0.80, 1.00, 0.95)
    colors[imgui.Col.Tab]                   = imgui.ImVec4(0.10, 0.25, 0.40, 0.85)
    colors[imgui.Col.TabHovered]            = imgui.ImVec4(0.35, 0.60, 0.90, 0.85)
    colors[imgui.Col.TabActive]             = imgui.ImVec4(0.25, 0.50, 0.75, 1.00)
    colors[imgui.Col.TextSelectedBg]        = imgui.ImVec4(0.35, 0.60, 1.00, 0.35)
    colors[imgui.Col.DragDropTarget]        = imgui.ImVec4(1.00, 1.00, 1.00, 0.90)
    colors[imgui.Col.NavHighlight]          = imgui.ImVec4(0.60, 0.80, 1.00, 0.80)
    colors[imgui.Col.NavWindowingHighlight] = imgui.ImVec4(1.00, 1.00, 1.00, 0.70)
    colors[imgui.Col.NavWindowingDimBg]     = imgui.ImVec4(0.80, 0.80, 0.80, 0.20)
    colors[imgui.Col.ModalWindowDimBg]      = imgui.ImVec4(0.20, 0.25, 0.30, 0.50)
    imgui.End()
    if show_extra_window[0] then
        local screenX, screenY = getScreenResolution()
        imgui.SetNextWindowPos(
            imgui.ImVec2(screenX / 2, screenY / 2),
            imgui.Cond.Always,
            imgui.ImVec2(0.5, 0.5)
        )
        imgui.SetNextWindowSize(imgui.ImVec2(300, 200), imgui.Cond.FirstUseEver)
        imgui.Begin(u8 "Доп Фиксы", show_extra_window,
            imgui.WindowFlags.NoCollapse + imgui.WindowFlags.AlwaysAutoResize)

        imgui.Text(u8 "1. FastLsa: Быстрая загрузка материалов в буррито на лса /flsa")
        imgui.Text(u8 "2. Бесконечный Бег")
        imgui.Text(u8 "3. DisaFlyingComponent: Отключает создание летающих компонентов транспорта при их поломке")
        imgui.Text(u8 "4. Отключение урона от взрывов")
        imgui.End()
    end
end)

local ANTILOMKA_ANIMS = {
    crckdeth1 = true,
    crckdeth3 = true
}

local KD_KO_ANIMS = {
    KD_left       = true,
    KD_right      = true,
    KO_shot_face  = true,
    KO_shot_front = true,
    KO_shot_stom  = true,
    KO_skid_back  = true,
    KO_skid_front = true,
    KO_spin_L     = true,
    KO_spin_R     = true
}

function samp.onApplyPlayerAnimation(
    playerId,
    animLib,
    animName,
    frameDelta,
    loop,
    lockX,
    lockY,
    freeze,
    time
)
    if antilomka[0] then
        if ANTILOMKA_ANIMS[animName] then
            return false
        end
    end


    if ddead[0] then
        if sampFindAnimationIdByNameAndFile(animName, animLib) == 1151 then
            emul_rpc("onPlayerStreamOut", { playerId })
        end
    end

    if ddead[0] then
        if KD_KO_ANIMS[animName] then
            emul_rpc("onPlayerStreamOut", { playerId })
        end
    end
end

function samp.onShowDialog(id, style, title, b1, b2, text)
    if fmembers[0] then
        if style ~= 4 and style ~= 5 and style ~= 2 then return end
        if not isSampAvailable() then return end

        local t = strip_colors(title or "")
        if not (t:find("Состав семьи") or t:find("^В%s*сети:%s*%d+%s*|%s*Состав семьи")) then
            return
        end

        local myid = -1
        local ok, lid = sampGetPlayerIdByCharHandle(PLAYER_PED)
        if ok then myid = lid end
        local mynick = (myid >= 0) and sampGetPlayerNickname(myid) or nil

        local out = {}
        for line in tostring(text):gmatch("[^\r\n]+") do
            local cols = {}
            for col in line:gmatch("[^\t]+") do cols[#cols + 1] = col end

            if cols[1] then
                local c1 = strip_colors(cols[1]):gsub("^%s+", "")
                local name, pid = c1:match("^(.-)%[(%d+)%]")
                if name and pid then
                    local i = tonumber(pid)
                    local color
                    if i and sampIsPlayerConnected(i) then
                        color = sampGetPlayerColor(i)
                    elseif mynick and name == mynick and myid >= 0 then
                        color = sampGetPlayerColor(myid)
                    end
                    if color and color ~= 0 then
                        local hex = string.format("%06X", color % 0x1000000)
                        cols[1] = "{" .. hex .. "}" .. name .. "[" .. pid .. "]{FFFFFF}"
                    end
                end
            end
            out[#out + 1] = table.concat(cols, "\t")
        end

        return { id, style, title, b1, b2, table.concat(out, "\n") }
    end
end

function samp.onServerMessage(color, text)
    if text:find('Открыл %{......%}доступ к складу') and autoget[0] then
        sampAddChatMessage(text, color)
        sampSendChat('/gg 0')
    end
end

function samp.onPlayerSync(playerId, data)
    if data.specialAction == 4 and sbivcarfix[0] then
        local result, ped = sampGetCharHandleBySampPlayerId(playerId)
        clearCharTasksImmediately(ped)
    end
end

function samp.onAttachObjectToPlayer(objectId, playerId, offsets, rotation)
    if dacs[0] then
        return false
    end
end

function samp.onSetPlayerAttachedObject(playerId, index, create, object)
    if dacs[0] then
        return false
    end
end

function imgui.Hint(str_id, hint, delay)
    local hovered = imgui.IsItemHovered()
    local animTime = 0.2
    local delay = delay or 0.00
    local show = true

    if not allHints then allHints = {} end
    if not allHints[str_id] then
        allHints[str_id] = {
            status = false,
            timer = 0
        }
    end

    if hovered then
        for k, v in pairs(allHints) do
            if k ~= str_id and os.clock() - v.timer <= animTime then
                show = false
            end
        end
    end

    if show and allHints[str_id].status ~= hovered then
        allHints[str_id].status = hovered
        allHints[str_id].timer = os.clock() + delay
    end

    if show then
        local between = os.clock() - allHints[str_id].timer
        if between <= animTime then
            local s = function(f)
                return f < 0.0 and 0.0 or (f > 1.0 and 1.0 or f)
            end
            local alpha = hovered and s(between / animTime) or s(1.00 - between / animTime)
            imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, alpha)
            imgui.SetTooltip(hint)
            imgui.PopStyleVar()
        elseif hovered then
            imgui.SetTooltip(hint)
        end
    end
end

function emul_rpc(name, args)
    local bs_io = require("samp.events.bitstream_io")

    local rpc = {
        onSetPlayerColor = { "int16", "int32", 72 },
        onPlayerStreamOut = { "int16", 163 }
    }

    local spec = rpc[name]
    if not spec then return end

    local bs = raknetNewBitStream()

    for i = 1, #spec - 1 do
        bs_io[spec[i]].write(bs, args[i])
    end

    raknetEmulRpcReceiveBitStream(spec[#spec], bs)
    raknetDeleteBitStream(bs)
end



function asyncHttpRequest(method, url, args, resolve, reject)
   local request_thread = effil.thread(function (method, url, args)
      local requests = require 'requests'
      local result, response = pcall(requests.request, method, url, args)
      if result then
         response.json, response.xml = nil, nil
         return true, response
      else
         return false, response
      end
   end)(method, url, args)
   -- Если запрос без функций обработки ответа и ошибок.
   if not resolve then resolve = function() end end
   if not reject then reject = function() end end
   -- Проверка выполнения потока
   lua_thread.create(function()
      local runner = request_thread
      while true do
         local status, err = runner:status()
         if not err then
            if status == 'completed' then
               local result, response = runner:get()
               if result then
                  resolve(response)
               else
                  reject(response)
               end
               return
            elseif status == 'canceled' then
               return reject(status)
            end
         else
            return reject(err)
         end
         wait(0)
      end
   end)
end

function msg(v) return sampAddChatMessage('{3E8FBF}[COLDBLOODED CULT]:{FFFFFF} ' .. v, -1) end
