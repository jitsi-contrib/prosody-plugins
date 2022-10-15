local jid = require("util.jid")
local util = module:require "util";
local is_healthcheck_room = util.is_healthcheck_room;
local extract_subdomain = util.extract_subdomain;

local max_occupants_for_rooms = module:get_option("max_occupants_for_rooms", {});
local max_occupants_for_subdomains = module:get_option("max_occupants_for_subdomains", {});

function handle_room_created(event)
    local room = event.room;

    if is_healthcheck_room(room.jid) then
        return;
    end

    local room_name = jid.node(room.jid);
    local subdomain = extract_subdomain(room_name);
    local max_occupants = max_occupants_for_rooms[room_name] or max_occupants_for_subdomains[subdomain];

    if max_occupants ~= nil then
         room._data.max_occupants = max_occupants;
    end
end

if next(max_occupants_for_subdomains) ~= nil or next(max_occupants_for_rooms) ~= nil then
    module:hook("muc-room-created", handle_room_created);
    module:log('info', 'loaded');
else
    module:log("info", "max_occupants_for_subdomains or max_occupants_for_rooms not configured. Nothing to do.");
end
