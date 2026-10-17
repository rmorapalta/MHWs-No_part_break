-- No Part Break v1.0 by KingStormhold
-- Breaks and severs still count for the game, they just never show on the monster.

local CONFIG = {
    -- Log breaks and blocked conditions to re2_framework_log.txt.
    debug = false,
    debug_lines = 8000,
    -- Heavy debug hooks. Leave them off, they can freeze the game.
    trace = false,
    mesh_trace = false,
    -- Extra debug logging for a few Arkveld methods.
    watch = {
        ["app.cEm0160Extend"] = {
            "breakGalianLeft", "breakGalianRight",
            "onChangeGallianNumState", "onChangeGallianNumStateDetail",
            "unleash", "recoveryAllScar", "doOnBreak_Parts",
            "onAbsorbStart", "onAbsorbFinish", "onAbsorbCocoon", "breakAbsorbCocoon",
        },
    },
    -- Frames a severed part is kept from dropping.
    detach_frames = 180,
    -- Parts that never break, by monster and break index.
    keep_intact = {
        -- Jin Dahaad iceplates: tail, cranial, abdominal, large exposed
        Em0162 = { [1] = true, [2] = true, [7] = true, [8] = true },
        -- Gypceros head crest, so it keeps its flash attack
        Em0009 = { [0] = true, [1] = true },
    },
    -- Breaks shown as in the base game.
    show_break = {
        -- Gogmazios back weapon
        Em0078 = { [1] = true },
    },
    -- Broken state -> intact state. Arkveld stores blade layout and wing breaks together.
    substitute = {
        -- blades joined
        ["6949aa65-0b7f-4f43-8f46-127a1f40305a"] = "9d6e5375-84fe-403a-b7f3-c47f8cc5425a",
        ["123d8273-9821-4738-98d9-e35a38bf7c6b"] = "9d6e5375-84fe-403a-b7f3-c47f8cc5425a",
        ["32b110bd-7ac2-43d3-a9db-28a2d23bda81"] = "9d6e5375-84fe-403a-b7f3-c47f8cc5425a",
        -- blades split
        ["0fb43d8b-bc2c-4993-bee1-499d76b4d0af"] = "92c47608-f0b5-4422-8456-d7f4a2091f61",
        ["83f15eb6-391d-4b67-a389-e1f0c3138886"] = "92c47608-f0b5-4422-8456-d7f4a2091f61",
        ["98d397e4-b725-44da-97bc-f62f3851f041"] = "92c47608-f0b5-4422-8456-d7f4a2091f61",
        -- mixed
        ["91e0e660-1c35-448d-a58a-8e72f4cfa583"] = "d16c7c6e-2261-4ccf-851c-4f1579e5383f",
        ["709caa83-a584-43ac-8384-dd6eebc873b6"] = "d16c7c6e-2261-4ccf-851c-4f1579e5383f",
        ["23217833-299f-4378-b7cc-010c434f049e"] = "d16c7c6e-2261-4ccf-851c-4f1579e5383f",
        -- mixed
        ["64a4e2f2-f63b-4346-8c2b-c49d2e9ba988"] = "10482214-37aa-4b0f-bd5f-27ead3e517b0",
        ["89f55309-52ce-4b41-bfc7-d29a44eece9e"] = "10482214-37aa-4b0f-bd5f-27ead3e517b0",
        ["8187c690-65c0-4726-a97f-2380b2c73423"] = "10482214-37aa-4b0f-bd5f-27ead3e517b0",
    },
    -- Conditions that are never blocked (static GUID lists in the monster's code).
    never_block = {
        -- Gogmazios tar and hidden weapons
        ["app.Em0078_00_Def"] = {
            "ENABLE_TAR_MCD", "DISABLE_TAR_MCD", "SOLID_MCD", "LIQUID_MCD", "GAS_MCD",
            "HIDDEN_ARTIAN_MCD", "HIDDEN_SLINGER_MCD",
        },
    },
}

if _G.__NoPartBreakInstalled then
    log.info("[NoPartBreak] already installed")
    return
end

_G.__NoPartBreakInstalled = true

local debug_left = CONFIG.debug_lines

local function info(msg)
    log.info("[NoPartBreak] " .. msg)
end

local function event(msg)
    if CONFIG.debug then
        log.info("[NoPartBreak] " .. msg)
    end
end

local function dbg(msg)
    if CONFIG.debug and debug_left > 0 then
        debug_left = debug_left - 1
        log.info("[NoPartBreak][dbg] " .. msg)
    end
end

local enemy_type = sdk.find_type_definition("app.EnemyCharacter")
local break_type = sdk.find_type_definition("app.cEmModuleParts.cBreakParts")
local base_extend = sdk.find_type_definition("app.cEnemyBossZakoExtend")
local parts_mgr_type = sdk.find_type_definition("ace.model_parts_manager.ModelPartsManager2")
local material_mgr_type = sdk.find_type_definition("ace.model_material_manager.ModelMaterialManager")
local guid_type = sdk.find_type_definition("System.Guid")

if not enemy_type then
    log.error("[NoPartBreak] app.EnemyCharacter not found, mod disabled")
    return
end

-- Helpers

local function key(v)
    return tostring(v)
end

local function raw_int(v)
    if v == nil then
        return nil
    end

    if type(v) == "number" then
        return math.tointeger(v) or v
    end

    local ok, n = pcall(function()
        return sdk.to_int64(v)
    end)

    if ok then
        return n
    end

    return nil
end

local function field(obj, name)
    local ok, value = pcall(function()
        return obj:get_field(name)
    end)

    if ok then
        return tostring(value)
    end

    return "?"
end

local function field_bool(obj, name)
    local ok, value = pcall(function()
        return obj:get_field(name)
    end)

    return ok and (value == true or value == 1)
end

local function guid_key(ptr)
    local ok, s = pcall(function()
        return sdk.to_valuetype(ptr, guid_type):call("ToString")
    end)

    if ok and s and tostring(s) ~= "" then
        return tostring(s)
    end

    return "ptr:" .. tostring(ptr)
end

local function find_method(td, name)
    if not td then
        return nil
    end

    return td:get_method(name)
end

local function returns_bool(m)
    local ok, name = pcall(function()
        return m:get_return_type():get_full_name()
    end)

    return ok and name == "System.Boolean"
end

-- Scopes

-- Monsters update on several threads at once, so scopes are tracked per thread.
local get_thread_id = function()
    return 0
end

if thread and thread.get_id then
    get_thread_id = function()
        local ok, id = pcall(thread.get_id)
        return ok and id or 0
    end
end

local visual_depth = {}
local break_depth = {}

local function enter(tbl)
    local t = get_thread_id()
    tbl[t] = (tbl[t] or 0) + 1
end

local function leave(tbl)
    local t = get_thread_id()
    local d = (tbl[t] or 1) - 1
    tbl[t] = d > 0 and d or nil
end

local function depth(tbl)
    return tbl[get_thread_id()] or 0
end

local hooked = {}

local function hook_scope(m, tbl, label)
    if not m or hooked[m] then
        return false
    end

    local ok = pcall(function()
        sdk.hook(m, function(args)
            enter(tbl)
        end, function(retval)
            leave(tbl)
            return retval
        end)
    end)

    if ok then
        hooked[m] = label
    end

    return ok
end

-- Break queries answer "not broken" while a visual method is running.
local masked_seen = {}

local function hook_query(m, label, zero_value)
    if not m or hooked[m] then
        return false
    end

    local ok = pcall(function()
        sdk.hook(m, function(args) end, function(retval)
            if depth(visual_depth) > 0 and sdk.to_int64(retval) ~= 0 then
                if not masked_seen[label] then
                    masked_seen[label] = true
                    dbg("masked " .. label)
                end

                return sdk.to_ptr(zero_value or 0)
            end

            return retval
        end)
    end)

    if ok then
        hooked[m] = label
    end

    return ok
end

-- Visual methods and break queries, found by name

local VISUAL_NAME = { "ModelCondition", "PartsDisp", "BreakModel" }
local QUERY_NAME = { "Break" }

local function matches_any(name, list, plain)
    for _, p in ipairs(list) do
        if name:find(p, 1, plain) then
            return true
        end
    end

    return false
end

local visual_count, query_count, event_count = 0, 0, 0

local function scan_type(td, label)
    for _, m in ipairs(td:get_methods()) do
        local name = m:get_name()

        if name == "doOnBreak_Parts" or name == "onBreak_Parts" then
            if hook_scope(m, break_depth, label .. "." .. name) then
                event_count = event_count + 1
            end
        elseif not name:find("^get_") and matches_any(name, VISUAL_NAME, true) then
            if hook_scope(m, visual_depth, label .. "." .. name) then
                visual_count = visual_count + 1
            end
        -- Getters are skipped: many of them share one engine function.
        elseif not name:find("^get_") and returns_bool(m) and matches_any(name, QUERY_NAME, true) then
            if hook_query(m, label .. "." .. name) then
                query_count = query_count + 1
            end
        end
    end
end

local trace_types = {}

for _, name in ipairs({ "setAngryModelCondition", "setModelDefaultCondition", "restoreModelPartsDisp", "setPartsDisp" }) do
    if hook_scope(find_method(enemy_type, name), visual_depth, "EnemyCharacter." .. name) then
        visual_count = visual_count + 1
    end
end

for _, m in ipairs(enemy_type:get_methods()) do
    local name = m:get_name()

    -- Compiler-generated name, its suffix changes between patches.
    if name:find("<setupBreakParts>", 1, true) and name:find("doBreak", 1, true) then
        if hook_scope(m, visual_depth, "EnemyCharacter.setupBreakParts.doBreak") then
            visual_count = visual_count + 1
        end
    end
end

-- evBreak_Parts is hooked further down.
event_count = event_count + 1

hook_query(find_method(break_type, "get_IsBreak"), "cBreakParts.get_IsBreak")
hook_query(find_method(break_type, "get_IsBreakAll"), "cBreakParts.get_IsBreakAll")
hook_query(find_method(break_type, "get_IsLostParts"), "cBreakParts.get_IsLostParts")
hook_query(find_method(break_type, "get_BreakCount"), "cBreakParts.get_BreakCount")

if base_extend then
    scan_type(base_extend, "cEnemyBossZakoExtend")
end

local extend_types = 0

for n = 0, 9999 do
    local base_name = string.format("app.cEm%04dExtend", n)
    local td = sdk.find_type_definition(base_name)

    if td then
        extend_types = extend_types + 1
        scan_type(td, string.format("cEm%04d", n))

        if n < 1000 then
            trace_types[#trace_types + 1] = { td, string.format("cEm%04d", n) }
        end

        for v = 0, 99 do
            local vt = sdk.find_type_definition(string.format("app.cEm%04d_%02dExtend", n, v))

            if vt then
                extend_types = extend_types + 1
                scan_type(vt, string.format("cEm%04d_%02d", n, v))

                if n < 1000 then
                    trace_types[#trace_types + 1] = { vt, string.format("cEm%04d_%02d", n, v) }
                end
            end
        end
    end
end

info(
    "hooked " .. extend_types .. " monster extends: " .. visual_count .. " visual methods, "
        .. query_count .. " break queries, " .. event_count .. " break events"
)

local trace_stack = {}

local function trace_top()
    local s = trace_stack[get_thread_id()]

    if not s or #s == 0 then
        return "-"
    end

    local from = math.max(1, #s - 2)
    return table.concat(s, ">", from, #s)
end

if CONFIG.debug and CONFIG.trace then
    local traced = 0

    for _, entry in ipairs(trace_types) do
        local td, label = entry[1], entry[2]

        for _, m in ipairs(td:get_methods()) do
            local name = m:get_name()

            if not name:find("^get_") and not name:find("^set_") and not name:find("ctor", 1, true) then
                local full = label .. "." .. name
                local ok = pcall(function()
                    sdk.hook(m, function(args)
                        local t = get_thread_id()
                        local s = trace_stack[t]

                        if not s then
                            s = {}
                            trace_stack[t] = s
                        end

                        s[#s + 1] = full
                    end, function(retval)
                        local s = trace_stack[get_thread_id()]

                        if s and #s > 0 then
                            s[#s] = nil
                        end

                        return retval
                    end)
                end)

                if ok then
                    traced = traced + 1
                end
            end
        end
    end

    info("debug trace on " .. traced .. " large-monster methods")
end

if CONFIG.debug then
    local watched = 0

    for type_name, names in pairs(CONFIG.watch) do
        local td = sdk.find_type_definition(type_name)

        for _, name in ipairs(names) do
            local m = td and td:get_method(name)
            local label = type_name:gsub("^app%.", "") .. "." .. name

            if not m then
                dbg("watch: " .. label .. " not found")
            else
                local ok = pcall(function()
                    sdk.hook(m, function(args)
                        local t = get_thread_id()
                        local s = trace_stack[t]

                        if not s then
                            s = {}
                            trace_stack[t] = s
                        end

                        s[#s + 1] = label

                        local extra = ""

                        if args[3] ~= nil then
                            extra = " a3=" .. tostring(raw_int(args[3]))
                        end

                        dbg("watch enter " .. label .. extra)
                    end, function(retval)
                        local s = trace_stack[get_thread_id()]

                        if s and #s > 0 then
                            s[#s] = nil
                        end

                        return retval
                    end)
                end)

                if ok then
                    watched = watched + 1
                end
            end
        end
    end

    info("debug watch on " .. watched .. " methods")
end

-- Block break visuals in the model and material managers

local blocked = {}
local owner_cache = {}

local any_break = false

local broken_owner_names = {}

local function owner_of(mgr_ptr)
    if not CONFIG.debug then
        return "?"
    end

    local k = key(mgr_ptr)
    local cached = owner_cache[k]

    if cached then
        return cached
    end

    local name = "?"

    pcall(function()
        local mgr = sdk.to_managed_object(mgr_ptr)
        local go = mgr:call("get_GameObject")
        name = tostring(go:call("get_Name"))
    end)

    owner_cache[k] = name
    return name
end

-- Severed-part conditions. Some monsters apply them after the break event returns.
local lost_conditions = {}

local show_depth = {}

-- The game fills these lists when the monster loads, so reading is retried.
local never_block = {}
local never_block_pending = {}

for type_name, fields in pairs(CONFIG.never_block) do
    for _, f in ipairs(fields) do
        never_block_pending[type_name .. "::" .. f] = { type_name, f }
    end
end

local function collect_guids(arr, out)
    local ok, elems = pcall(function()
        return arr:get_elements()
    end)

    if not ok or not elems then
        return 0
    end

    local n = 0

    for _, e in ipairs(elems) do
        local s = nil

        pcall(function()
            s = tostring(e:call("ToString"))
        end)

        if s and s:match("^%x+%-%x+%-%x+%-%x+%-%x+$") then
            out[s] = true
            n = n + 1
        else
            -- Guid[][]
            n = n + collect_guids(e, out)
        end
    end

    return n
end

local function load_never_block()
    for k, entry in pairs(never_block_pending) do
        local td = sdk.find_type_definition(entry[1])
        local fd = td and td:get_field(entry[2])
        local arr = nil

        if fd then
            pcall(function()
                arr = fd:get_data(nil)
            end)
        end

        if arr then
            local n = collect_guids(arr, never_block)

            if n > 0 then
                never_block_pending[k] = nil
                info("never block " .. k .. ": " .. n .. " conditions")
            end
        end
    end
end

-- Guids for CONFIG.substitute. This game's System.Guid uses mData* fields.
local guid_cache = {}
local substitution_ok = true

local function guid_by_fields(hex)
    local v = ValueType.new(guid_type)
    v:set_field("mData1", tonumber(hex:sub(1, 8), 16))
    v:set_field("mData2", tonumber(hex:sub(9, 12), 16))
    v:set_field("mData3", tonumber(hex:sub(13, 16), 16))

    for i = 0, 7 do
        local b = 17 + i * 2
        v:set_field("mData4_" .. i, tonumber(hex:sub(b, b + 1), 16))
    end

    return v
end

local function guid_by_parse(s)
    local parse = guid_type:get_method("Parse(System.String)")
    return parse:call(nil, sdk.create_managed_string(s))
end

local function make_guid(s)
    local cached = guid_cache[s]

    if cached then
        return cached
    end

    local hex = s:gsub("-", "")

    if #hex ~= 32 or not guid_type then
        return nil
    end

    local tried = {}

    for _, builder in ipairs({
        { "fields", function() return guid_by_fields(hex) end },
        { "parse", function() return guid_by_parse(s) end },
    }) do
        local ok, vt = pcall(builder[2])
        local addr, back = nil, nil

        if ok and vt then
            pcall(function()
                addr = vt:address()
            end)

            if addr then
                back = guid_key(addr)
            end
        end

        if back == s then
            guid_cache[s] = { vt = vt, addr = addr }
            dbg("guid built by " .. builder[1] .. ": " .. s)
            return guid_cache[s]
        end

        tried[#tried + 1] = builder[1] .. "(ok=" .. tostring(ok) .. " addr=" .. tostring(addr)
            .. " back=" .. tostring(back) .. ")"
    end

    log.error("[NoPartBreak] could not build Guid " .. s .. ": " .. table.concat(tried, " "))
    return nil
end

local never_block_tries = 0

local function is_never_block(guid)
    if next(never_block_pending) then
        never_block_tries = never_block_tries + 1

        if never_block_tries % 50 == 1 then
            load_never_block()
        end
    end

    return never_block[guid] == true
end

local function guard_condition(label)
    return function(args)
        if depth(show_depth) > 0 then
            return
        end

        local guid = guid_key(args[4])

        local twin = substitution_ok and CONFIG.substitute[guid]

        if twin then
            local g = make_guid(twin)

            if g then
                args[4] = sdk.to_ptr(g.addr)
                dbg(label .. " swapped " .. guid .. " -> " .. twin .. " owner=" .. owner_of(args[2]))
                return
            end

            -- Fall back to blocking.
            substitution_ok = false
            log.error("[NoPartBreak] could not build a Guid, substitution disabled")
        end

        local mgr = key(args[2])
        local list = blocked[mgr]

        if list and list[guid] then
            if is_never_block(guid) then
                list[guid] = nil
                return
            end

            dbg(label .. " blocked again owner=" .. owner_of(args[2]) .. " guid=" .. guid .. " by=" .. trace_top())
            return sdk.PreHookResult.SKIP_ORIGINAL
        end

        if lost_conditions[guid] or (depth(break_depth) > 0 and depth(visual_depth) == 0) then
            if is_never_block(guid) then
                dbg(label .. " never blocked (monster state) owner=" .. owner_of(args[2]) .. " guid=" .. guid)
                return
            end

            list = list or {}
            list[guid] = true
            blocked[mgr] = list
            dbg(label .. " blocked break visual owner=" .. owner_of(args[2]) .. " guid=" .. guid .. " by=" .. trace_top())
            return sdk.PreHookResult.SKIP_ORIGINAL
        end

        if depth(break_depth) > 0 then
            dbg(label .. " passed (intact, visual scope) owner=" .. owner_of(args[2]) .. " guid=" .. guid .. " by=" .. trace_top())
        elseif CONFIG.debug and any_break then
            local owner = owner_of(args[2])

            if broken_owner_names[owner] then
                dbg(
                    label .. " passed owner=" .. owner .. " guid=" .. guid
                        .. " visual=" .. depth(visual_depth) .. " by=" .. trace_top()
                )
            end
        end
    end
end

local function pass_retval(retval)
    return retval
end

local parts_set = find_method(parts_mgr_type, "setCondition")
local material_set = find_method(material_mgr_type, "setCondition")

if parts_set then
    sdk.hook(parts_set, guard_condition("parts"), pass_retval)
else
    log.error("[NoPartBreak] ModelPartsManager2.setCondition not found")
end

if material_set then
    sdk.hook(material_set, guard_condition("material"), pass_retval)
else
    log.error("[NoPartBreak] ModelMaterialManager.setCondition not found")
end

local parts_lost_type = sdk.find_type_definition("app.user_data.EmParamPartsLost")
local lost_hooks = 0

if parts_lost_type then
    for _, m in ipairs(parts_lost_type:get_methods()) do
        if m:get_name():find("^getPartsLost") and m:get_name() ~= "getPartsLostCount" then
            local ok = pcall(function()
                sdk.hook(m, function(args) end, function(retval)
                    pcall(function()
                        local lost = sdk.to_managed_object(retval)

                        if lost then
                            local g = tostring(lost:call("get_ModelConditionGuid"):call("ToString"))

                            if not lost_conditions[g] then
                                lost_conditions[g] = true
                                dbg("lost-part condition " .. g)
                            end
                        end
                    end)

                    return retval
                end)
            end)

            if ok then
                lost_hooks = lost_hooks + 1
            end
        end
    end
end

if lost_hooks == 0 then
    log.error("[NoPartBreak] EmParamPartsLost lookups not found")
end

if CONFIG.debug and CONFIG.mesh_trace then
    local mesh_type = sdk.find_type_definition("via.render.Mesh")
    local float4_type = sdk.find_type_definition("via.Float4")
    local mesh_owner = {}
    local last_value = {}

    local function mesh_owner_of(ptr)
        local k = key(ptr)
        local o = mesh_owner[k]

        if o then
            return o
        end

        o = "?"

        pcall(function()
            o = tostring(sdk.to_managed_object(ptr):call("get_GameObject"):call("get_Name"))
        end)

        mesh_owner[k] = o
        return o
    end

    local function read_float(a)
        return string.format("%.3f", sdk.to_float(a))
    end

    local function read_float4(a)
        local v = sdk.to_valuetype(a, float4_type)
        return string.format(
            "(%.2f,%.2f,%.2f,%.2f)",
            v:get_field("x"), v:get_field("y"), v:get_field("z"), v:get_field("w")
        )
    end

    local function hook_mesh_write(name, reader)
        local m = find_method(mesh_type, name)

        if not m then
            dbg("via.render.Mesh." .. name .. " not found")
            return
        end

        pcall(function()
            sdk.hook(m, function(args)
                if not any_break then
                    return
                end

                local owner = mesh_owner_of(args[2])

                if not owner:find("^Em0") then
                    return
                end

                local mat, var = raw_int(args[3]), raw_int(args[4])
                local ok, value = pcall(reader, args[5])
                value = ok and value or "?"

                local k = key(args[2]) .. ":" .. tostring(mat) .. ":" .. tostring(var)

                if last_value[k] == value then
                    return
                end

                last_value[k] = value

                local mname, vname = tostring(mat), tostring(var)

                pcall(function()
                    local mesh = sdk.to_managed_object(args[2])
                    mname = tostring(mesh:call("getMaterialName", mat))
                    vname = tostring(mesh:call("getMaterialVariableName", mat, var))
                end)

                dbg(
                    "mesh " .. name .. " owner=" .. owner .. " " .. mname .. "." .. vname
                        .. "=" .. value .. " by=" .. trace_top()
                )
            end, pass_retval)
        end)
    end

    hook_mesh_write("setMaterialFloat", read_float)
    hook_mesh_write("setMaterialFloat4", read_float4)
end

-- Notification, effect and severed parts

local notify_break = find_method(break_type, "get_IsNotificationBreakInfo")

if notify_break then
    sdk.hook(notify_break, function(args) end, function(retval)
        return sdk.to_ptr(0)
    end)
else
    log.error("[NoPartBreak] get_IsNotificationBreakInfo not found")
end

local break_effect = find_method(enemy_type, "callBreakPartsEffect")

if break_effect then
    sdk.hook(break_effect, function(args)
        return sdk.PreHookResult.SKIP_ORIGINAL
    end, pass_retval)
else
    log.error("[NoPartBreak] callBreakPartsEffect not found")
end

local pending_detach_frames = 0
local detach = {}

local recent_breaks = {}

-- keep_intact parts: once seen, breakParts never runs for them again.
local kept_objs = {}

local break_method = find_method(break_type, "breakParts")

if break_method then
    local current = {}

    sdk.hook(break_method, function(args)
        local k = key(args[2])

        if kept_objs[k] then
            return sdk.PreHookResult.SKIP_ORIGINAL
        end

        current[get_thread_id()] = { k = k, obj = sdk.to_managed_object(args[2]) }
    end, function(retval)
        local t = get_thread_id()
        local entry = current[t]
        current[t] = nil

        local obj = entry and entry.obj

        if obj then
            local list = recent_breaks[t] or {}
            list[#list + 1] = entry
            recent_breaks[t] = list

            if field_bool(obj, "_IsDetachParts") then
                pending_detach_frames = 30
            end

            event(
                "break param=" .. field(obj, "_BreakParamIndex")
                    .. " count=" .. field(obj, "_BreakCount")
                    .. " detach=" .. field(obj, "_IsDetachParts")
            )
        end

        return retval
    end)
end

local species_cache = {}
local go_name_cache = {}

local function species_of(enemy_ptr)
    local k = key(enemy_ptr)
    local s = species_cache[k]

    if s then
        return s
    end

    s = "?"

    pcall(function()
        local name = tostring(sdk.to_managed_object(enemy_ptr):call("get_GameObject"):call("get_Name"))
        go_name_cache[k] = name
        s = name:match("^(Em%d%d%d%d)") or name
    end)

    species_cache[k] = s
    return s
end

local function undo_break(obj)
    for _, name in ipairs({ "_BreakCount", "_TotalBreakCount" }) do
        pcall(function()
            local n = obj:get_field(name)

            if n and n > 0 then
                obj:set_field(name, n - 1)
            end
        end)
    end
end

local ev_break = find_method(enemy_type, "evBreak_Parts")

local ev_kind = {}

if ev_break then
    sdk.hook(ev_break, function(args)
        any_break = true

        local t = get_thread_id()
        local broken = recent_breaks[t] or {}
        recent_breaks[t] = nil
        ev_kind[t] = nil

        local part = raw_int(args[3])
        local species = species_of(args[2])
        local keep = CONFIG.keep_intact[species]
        local show = CONFIG.show_break[species]

        event("evBreak_Parts enemy=" .. key(args[2]) .. " species=" .. species .. " part=" .. tostring(part))

        local go_name = go_name_cache[key(args[2])]

        if go_name then
            broken_owner_names[go_name] = true
        end

        if keep and keep[part] then
            for _, entry in ipairs(broken) do
                if field(entry.obj, "_BreakParamIndex") == tostring(part) then
                    undo_break(entry.obj)
                    kept_objs[entry.k] = true
                end
            end

            event("kept intact " .. species .. " part=" .. tostring(part))
            return sdk.PreHookResult.SKIP_ORIGINAL
        end

        if show and show[part] then
            pending_detach_frames = 0
            ev_kind[t] = "show"
            enter(show_depth)
            event("vanilla break " .. species .. " part=" .. tostring(part))
            return
        end

        ev_kind[t] = "break"
        enter(break_depth)

        if pending_detach_frames > 0 then
            pending_detach_frames = 0
            detach[key(args[2])] = CONFIG.detach_frames
            args[5] = sdk.to_ptr(0)
            event("sever on enemy=" .. key(args[2]) .. ", lost part blocked")
        end
    end, function(retval)
        local t = get_thread_id()
        local kind = ev_kind[t]
        ev_kind[t] = nil

        if kind == "break" then
            leave(break_depth)
        elseif kind == "show" then
            leave(show_depth)
        end

        return retval
    end)
end

local function hook_detach_block(name)
    local m = find_method(enemy_type, name)

    if not m then
        log.error("[NoPartBreak] " .. name .. " not found")
        return
    end

    sdk.hook(m, function(args)
        if (detach[key(args[2])] or 0) > 0 then
            event("blocked " .. name)
            return sdk.PreHookResult.SKIP_ORIGINAL
        end
    end, pass_retval)
end

hook_detach_block("partsLoss")
hook_detach_block("flyLostParts")

-- Timers

re.on_frame(function()
    if pending_detach_frames > 0 then
        pending_detach_frames = pending_detach_frames - 1
    end

    for k, frames in pairs(detach) do
        detach[k] = frames > 1 and frames - 1 or nil
    end
end)

info("v1.0 active (debug=" .. tostring(CONFIG.debug) .. ")")
