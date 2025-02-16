local LOGLEVEL = "debug"
local TIMEOUT = module:get_option_number("party_check_timeout", 60)

local is_admin = require "core.usermanager".is_admin
local is_healthcheck_room = module:require "util".is_healthcheck_room
local it = require "util.iterators"
local st = require "util.stanza"

local muc_domain_base = module:get_option_string("muc_mapper_domain_base");
local main_muc_component_host = module:get_option_string("muc_component");
local breakout_muc_component_host = module:get_option_string("breakout_component", "breakout." .. muc_domain_base);

-- dict of room jid to timer object
local room_timers = {}

local main_muc_service; -- luacheck: ignore

module:log(LOGLEVEL, "loaded")

local function _is_admin(jid)
    return is_admin(jid, module.host)
end

-- Helper function to wait till a component is loaded before running the given callback
local function run_when_component_loaded(component_host_name, callback)
    local function trigger_callback()
        module:log('info', 'Component loaded %s', component_host_name);
        callback(module:context(component_host_name), component_host_name);
    end

    if prosody.hosts[component_host_name] == nil then
        module:log('debug', 'Host %s not yet loaded. Will trigger when it is loaded.', component_host_name);
        prosody.events.add_handler('host-activated', function (host)
            if host == component_host_name then
                trigger_callback();
            end
        end);
    else
        trigger_callback();
    end
end

-- Helper function to wait till a component's muc module is loaded before running the given callback
local function run_when_muc_module_loaded(component_host_module, component_host_name, callback)
    local function trigger_callback()
        module:log('info', 'MUC module loaded for %s', component_host_name);
        callback(prosody.hosts[component_host_name].modules.muc, component_host_module);
    end

    if prosody.hosts[component_host_name].modules.muc == nil then
        module:log('debug', 'MUC module for %s not yet loaded. Will trigger when it is loaded.', component_host_name);
        prosody.hosts[component_host_name].events.add_handler('module-loaded', function(event)
            if (event.module == 'muc') then
                trigger_callback();
            end
        end);
    else
        trigger_callback()
    end
end

-- No easy way to infer main room from breakout room object, so search all rooms in main muc component and cache
-- it on room so we don't have to search again
-- Speakerstats component does exactly the same thing, so if that is loaded, we get this for free.
local function get_main_room(breakout_room)
    if breakout_room._data and breakout_room._data.main_room then
        return breakout_room._data.main_room;
    end

    -- let's search all rooms to find the main room
    for room in main_muc_service.each_room() do
        if room._data and room._data.breakout_rooms_active and room._data.breakout_rooms[breakout_room.jid] then
            breakout_room._data.main_room = room;
            return room;
        end
    end
end

local function destroy_room (room)
    -- delete timer for room
    room_timers[room.jid] = nil

    if is_healthcheck_room(room.jid) then
        return
    end

    -- last check before destroying the room
    -- if an owner is still here, cancel
    for _, o in room:each_occupant() do
        if not _is_admin(o.jid) then
            if room:get_affiliation(o.jid) == "owner" then
                module:log(
                    LOGLEVEL,
                    "timer: an owner is still here, %s",
                    o.jid
                )
                return
            end
        end
    end

    -- terminate the meeting
    room:set_persistent(false)
    room:destroy(nil, "The meeting has been terminated")
    module:log(LOGLEVEL, "the party is over")
end

local function occupant_left_breakout (event)
    local breakout_room, occupant = event.room, event.occupant

    if is_healthcheck_room(breakout_room.jid) or _is_admin(occupant.jid) then
        return
    end

    -- no need to do anything for normal participant
    if breakout_room:get_affiliation(occupant.jid) ~= "owner" then
        module:log(LOGLEVEL, "a participant left breakout, %s", occupant.jid)
        return
    end

    module:log(LOGLEVEL, "an owner left breakout, %s", occupant.jid)
    
    local main_room = get_main_room(breakout_room)

    -- check if there is any other owner in the main room
    for _, o in main_room:each_occupant() do
        if not _is_admin(o.jid) then
            if main_room:get_affiliation(o.jid) == "owner" then
                module:log(LOGLEVEL, "an owner is still in the main room, %s", o.jid)
                return
            end
        end
    end

    -- since there is no other owner, destroy the main room after TIMEOUT secs
    room_timers[main_room.jid] = module:add_timer(TIMEOUT, function ()
        destroy_room(main_room)
    end)
end

local function occupant_joined_breakout (event)
    local breakout_room, occupant = event.room, event.occupant

    if is_healthcheck_room(breakout_room.jid) or _is_admin(occupant.jid) then
        return
    end

    -- no need to do anything for normal participant
    if breakout_room:get_affiliation(occupant.jid) ~= "owner" then
        module:log(LOGLEVEL, "a participant joined breakout, %s", occupant.jid)
        return
    end

    local main_room = get_main_room(breakout_room)

    -- stop & delete a timer, if present
    if room_timers[main_room.jid] ~= nil then
        room_timers[main_room.jid]:stop()
        room_timers[main_room.jid] = nil
    end

    module:log(LOGLEVEL, "an owner joined breakout, %s", occupant.jid)
end

module:hook("muc-occupant-pre-join", function (event)
    local room, stanza = event.room, event.stanza
    local user_jid = stanza.attr.from

    if is_healthcheck_room(room.jid) or _is_admin(user_jid) then
        module:log(LOGLEVEL, "location check, %s", user_jid)
        return
    end

    -- if an owner joins, start the party
    local context_user = event.origin.jitsi_meet_context_user
    if context_user then
        if context_user["affiliation"] == "owner" or
           context_user["affiliation"] == "moderator" or
           context_user["affiliation"] == "teacher" or
           context_user["moderator"] == "true" or
           context_user["moderator"] == true then
            -- stop & delete a timer, if present
            if room_timers[room.jid] ~= nil then
                room_timers[room.jid]:stop()
                room_timers[room.jid] = nil
            end

            module:log(LOGLEVEL, "an owner joined the party, %s", user_jid)
            return
        end
    end

    -- if the party has not started yet, don't accept the participant
    local occupant_count = it.count(room:each_occupant())
    if occupant_count < 2 then
        module:log(LOGLEVEL, "the party is not started yet")
        event.origin.send(st.error_reply(stanza, 'cancel', 'not-allowed'))
        return true
    end
end)

module:hook("muc-occupant-left", function (event)
    local room, occupant = event.room, event.occupant

    if is_healthcheck_room(room.jid) or _is_admin(occupant.jid) then
        return
    end

    -- no need to do anything for normal participant
    if room:get_affiliation(occupant.jid) ~= "owner" then
        module:log(LOGLEVEL, "a participant left, %s", occupant.jid)
        return
    end

    module:log(LOGLEVEL, "an owner left, %s", occupant.jid)

    -- check if there is any other owner here
    for _, o in room:each_occupant() do
        if not _is_admin(o.jid) then
            if room:get_affiliation(o.jid) == "owner" then
                module:log(LOGLEVEL, "an owner is still here, %s", o.jid)
                return
            end
        end
    end

    -- since there is no other owner, destroy the room after TIMEOUT secs
    room_timers[room.jid] = module:add_timer(TIMEOUT, function ()
        destroy_room(room)
    end)
end)

-- Handle events on main muc module
run_when_component_loaded(main_muc_component_host, function(host_module, host_name)
    run_when_muc_module_loaded(host_module, host_name, function (main_muc, main_module)
        main_muc_service = main_muc;  -- so it can be accessed from breakout muc event handlers
    end);
end);

-- Handle events on breakout muc module
run_when_component_loaded(breakout_muc_component_host, function(host_module, host_name)
    run_when_muc_module_loaded(host_module, host_name, function (_, breakout_module)
        -- the following must run after speakerstats (priority -1)
        breakout_module:hook("muc-occupant-joined", occupant_joined_breakout, -2);
        breakout_module:hook("muc-occupant-left", occupant_left_breakout, -2);
    end);
end);