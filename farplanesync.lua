--[[
    farplanesync for Ashita v4 - PhoenixXI

    Keeps your Farplane linkshell portal (farplane.org/portal) up to date from the game, so you
    don't have to tick milestones by hand. It reads what the client already knows about your own
    character (job levels, nation and rank, key items, and the quest and mission logs the server
    sends in packet 0x056) and writes it to a JSON file in this addon's out\ folder whenever it
    changes.

    The addon never goes online and never sends anything to the game server. Uploading is done by a
    separate helper outside the game (tools\uploader.bat), which posts the file to farplane.org with
    your personal portal key. Without the helper running, nothing leaves your PC.
]]

addon.name    = 'farplanesync';
addon.author  = 'Spongeh';
addon.version = '0.1.1';
addon.desc    = 'Writes your job levels, key items, quests and missions to a file for the Farplane portal uploader.';
addon.link    = 'https://github.com/rhaba/farplanesync';

require('common');
local chat = require('chat');
local settings = require('settings');
local json = require('fps.json');

local JOBS = { 'WAR', 'MNK', 'WHM', 'BLM', 'RDM', 'THF', 'PLD', 'DRK', 'BST', 'BRD', 'RNG', 'SAM',
    'NIN', 'DRG', 'SMN', 'BLU', 'COR', 'PUP', 'DNC', 'SCH' };
local NATIONS = { [0] = "San d'Oria", [1] = 'Bastok', [2] = 'Windurst' };
local MAX_KEY_ITEM = 3300;   -- highest key item id checked (PhoenixXI key_item.yaml tops out below this)

-- Saved per character (Ashita keeps one settings file per character), so a snapshot written after
-- reloading the addon still has the logs the server sent at login.
local defaults = T{
    quests = T{ current = T{}, completed = T{} },   -- [log] = { quest ids }
    missions = T{},                                  -- see onMissions
};
local cfg = settings.load(defaults);
settings.register('settings', 'farplanesync_settings_update', function (s) if s ~= nil then cfg = s; end end);

local function msg(text)
    print(chat.header(addon.name):append(chat.message(text)));
end

local dirty, writeAt, lastWrite, lastFile = false, 0, nil, nil;
local function changed()
    dirty = true;
    writeAt = os.clock() + 5;   -- wait for a burst of packets to settle
end

-- ---------- packet 0x056: quest and mission logs ----------
-- Layout (LandSandBoat src/map/packets/s2c/0x056_mission*.cpp): eight uint32 Data words at 0x04,
-- Port (which log) at 0x24. Offsets below include the 4-byte packet header.

local function word(data, i) return struct.unpack('I', data, 0x04 + i * 4 + 1); end

-- Ids whose bit is set in Data words [first, last]; bit 0 of word `first` is id 0.
local function bitIds(data, first, last)
    local ids = T{};
    for w = first, last do
        local v = word(data, w);
        if v ~= 0 then
            for b = 0, 31 do
                if bit.band(v, bit.lshift(1, b)) ~= 0 then ids:append((w - first) * 32 + b); end
            end
        end
    end
    return ids;
end

local function same(a, b)
    if a == nil or b == nil or #a ~= #b then return false; end
    for i = 1, #a do if a[i] ~= b[i] then return false; end end
    return true;
end

local function set(tbl, key, value)
    if type(value) == 'table' then
        if same(tbl[key], value) then return; end
    elseif tbl[key] == value then
        return;
    end
    tbl[key] = value;
    settings.save();
    changed();
end

local function onLogPacket(data)
    local port = struct.unpack('H', data, 0x24 + 1);
    local m = cfg.missions;
    if port == 0xFFFF then
        -- current missions: nation, nation mission, Zilart, Promathia
        set(m, 'nation', word(data, 0));
        set(m, 'nation_current', word(data, 1));
        set(m, 'zilart_current', word(data, 2));
        set(m, 'cop_current', word(data, 3));
    elseif port >= 0x50 and port <= 0x80 and port % 8 == 0 then
        local log = (port - 0x50) / 8;
        if log == 6 then
            -- Aht Urhgan: quest flags only fill words 0-3; 4 = Assault, 5 = ToAU mission (current)
            set(cfg.quests.current, tostring(log), bitIds(data, 0, 3));
            set(m, 'assault_current', word(data, 4));
            set(m, 'toau_current', word(data, 5));
        else
            set(cfg.quests.current, tostring(log), bitIds(data, 0, 7));
        end
    elseif port >= 0x90 and port <= 0xC0 and port % 8 == 0 then
        local log = (port - 0x90) / 8;
        if log == 6 then
            set(cfg.quests.completed, tostring(log), bitIds(data, 0, 3));
            set(m, 'assault_completed', bitIds(data, 4, 7));
        else
            set(cfg.quests.completed, tostring(log), bitIds(data, 0, 7));
        end
    elseif port == 0xD0 then
        -- completed missions: San d'Oria, Bastok, Windurst, Zilart (two words each)
        set(m, 'sandoria_completed', bitIds(data, 0, 1));
        set(m, 'bastok_completed', bitIds(data, 2, 3));
        set(m, 'windurst_completed', bitIds(data, 4, 5));
        set(m, 'zilart_completed', bitIds(data, 6, 7));
    elseif port == 0xD8 then
        set(m, 'toau_completed', bitIds(data, 0, 1));
    end
end

ashita.events.register('packet_in', 'farplanesync_packet', function (e)
    if e.id == 0x056 then
        local ok, err = pcall(onLogPacket, e.data);
        if not ok then msg('Error reading the quest log: ' .. tostring(err)); end
    end
end);

-- ---------- character (from client memory) ----------

local function call(obj, fn, ...)
    if obj == nil or obj[fn] == nil then return nil; end
    local ok, v = pcall(obj[fn], obj, ...);
    if ok then return v; end
    return nil;
end

local function charName()
    local party = AshitaCore:GetMemoryManager():GetParty();
    local name = call(party, 'GetMemberName', 0);
    if name == nil or name == '' then return nil; end
    return name;
end

local function keyItems()
    local player = AshitaCore:GetMemoryManager():GetPlayer();
    local held = T{};
    for id = 0, MAX_KEY_ITEM do
        if call(player, 'HasKeyItem', id) then held:append(id); end
    end
    return held;
end

local function snapshot()
    local name = charName();
    if name == nil then return nil; end
    local player = AshitaCore:GetMemoryManager():GetPlayer();
    local jobs = {};
    for i, j in ipairs(JOBS) do
        local lv = call(player, 'GetJobLevel', i) or 0;
        if lv > 0 then jobs[j] = lv; end
    end
    local main, sub = call(player, 'GetMainJob') or 0, call(player, 'GetSubJob') or 0;
    return {
        addon = addon.name,
        version = addon.version,
        name = name,
        written_at = os.time(),
        main_job = JOBS[main],
        main_level = call(player, 'GetMainJobLevel'),
        sub_job = JOBS[sub],
        sub_level = sub > 0 and call(player, 'GetSubJobLevel') or nil,
        nation = NATIONS[call(player, 'GetNation') or -1],
        rank = call(player, 'GetRank'),
        jobs = jobs,
        key_items = keyItems(),
        quests = cfg.quests,
        missions = cfg.missions,
    };
end

-- out\<Name>.json; written to a temp file first so the uploader never reads half a file
local function write(force)
    local snap = snapshot();
    if snap == nil then return false, 'Not logged in yet.'; end
    local body = json.encode(snap);
    -- compare without the timestamp so an unchanged character isn't rewritten
    local key = body:gsub('"written_at":%d+,?', '');
    if not force and key == lastWrite then return true, 'No changes.'; end
    ashita.fs.create_directory(addon.path .. 'out');
    local file = addon.path .. 'out\\' .. snap.name .. '.json';
    local f = io.open(file .. '.tmp', 'w');
    if f == nil then return false, 'Could not write ' .. file; end
    f:write(body);
    f:close();
    os.remove(file);
    os.rename(file .. '.tmp', file);
    lastWrite, lastFile = key, file;
    return true, 'Wrote out\\' .. snap.name .. '.json';
end

local nextCheck = 0;
ashita.events.register('d3d_present', 'farplanesync_present', function ()
    local now = os.clock();
    if dirty and now >= writeAt then
        dirty = false;
        write(false);
    end
    -- levels, rank and key items aren't announced by a packet we read, so look every 30 s
    if now >= nextCheck then
        nextCheck = now + 30;
        if not dirty then write(false); end
    end
end);

ashita.events.register('command', 'farplanesync_command', function (e)
    local args = e.command:args();
    if #args == 0 or (args[1] ~= '/farplanesync' and args[1] ~= '/fpsync') then return; end
    e.blocked = true;
    local sub = (args[2] or ''):lower();
    if sub == 'write' then
        local _, text = write(true);
        msg(text);
    elseif sub == 'upload' then
        local bat = addon.path .. 'tools\\uploader.bat';
        local probe = io.open(bat, 'r');
        if probe == nil then msg('Missing tools\\uploader.bat (reinstall farplanesync).'); return; end
        probe:close();
        os.execute('start "farplanesync uploader" "' .. bat .. '"');
        msg('Uploader window opening. Leave it running while you play; close it to stop.');
    else
        local m, q = cfg.missions, cfg.quests;
        local logs = 0;
        for _ in pairs(q.completed) do logs = logs + 1; end
        msg(('Quest logs seen: %d/7. Missions: %s. Last file: %s'):format(logs,
            m.nation ~= nil and 'yes' or 'not yet (zone once)', lastFile or 'none yet'));
        msg('/fpsync write - write the file now. /fpsync upload - start the uploader (outside the game).');
    end
end);

ashita.events.register('load', 'farplanesync_load', function ()
    nextCheck = os.clock() + 10;
end);
