local LOGLEVEL = "debug"
local jid = require("util.jid")
local util = module:require 'util'
local it = require "util.iterators"
local st = require "util.stanza"
local timer = require "util.timer"
local is_healthcheck_room = util.is_healthcheck_room
local extract_subdomain = util.extract_subdomain;

local conference_max_minutes = module:get_option("conference_max_minutes", {});
local max_minutes_for_rooms = module:get_option("max_minutes_for_rooms", {});
local max_minutes_for_subdomains = module:get_option("max_minutes_for_subdomains", {});

function handle_room_created(event)
    local room = event.room

    if is_healthcheck_room(room.jid) then
        module:log(LOGLEVEL, "skip restriction")
        return
    end

    local room_name = jid.node(room.jid);
    local subdomain = extract_subdomain(room_name);
    local max_minutes = max_minutes_for_rooms[room_name] or max_minutes_for_subdomains[subdomain] or conference_max_minutes;
    local TIMEOUT = max_minutes * 60
    
    -- announce the expiration time
    room:broadcast_message(
        st.message({ type="groupchat", from=room.jid })
        :tag("body")
        :text("The conference will be terminated in "..max_minutes.." min"))

    module:log(
        LOGLEVEL, "set timeout for conference, %s secs, %s",
        TIMEOUT,
	room.jid
    )

    timer.add_task(TIMEOUT, function()
        if is_healthcheck_room(room.jid) then
            return
        end

        local occupant_count = it.count(room:each_occupant())
        if occupant_count == 0 then
            return
        end

        -- terminate the meeting
        room:set_persistent(false)
        room:destroy(nil, "The meeting has been terminated")
        module:log(LOGLEVEL, "the conference terminated")
    end)
end

if next(max_minutes_for_subdomains) ~= nil or next(max_minutes_for_rooms) ~= nil or next(conference_max_minutes) ~= nil then
    module:hook("muc-room-created", handle_room_created);
    module:log('info', 'loaded');
else
    module:log("info", "max_minutes_for_subdomains or max_minutes_for_rooms not configured. Nothing to do.");
end