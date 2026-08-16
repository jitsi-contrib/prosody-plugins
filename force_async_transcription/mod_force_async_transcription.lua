local util = module:require 'util';
local is_healthcheck_room = util.is_healthcheck_room;
module:log("info", "loaded")

-- -----------------------------------------------------------------------------
module:hook("muc-room-created", function(event)
    local room = event.room

    if is_healthcheck_room(room.jid) then
        return
    end

    if not room.jitsiMetadata then
        room.jitsiMetadata = {}
    end

    room.jitsiMetadata.asyncTranscription = true
    module:log("debug", "forced asyncTranscription for %s", room.jid)

-- run after mod_room_metadata_component, which initializes room.jitsiMetadata
-- on the same event at priority -1
end, -2)
