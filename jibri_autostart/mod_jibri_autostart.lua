local LOGLEVEL = "info"

local util = module:require 'util';
local is_admin = util.is_admin;
local is_healthcheck_room = util.is_healthcheck_room
local timer = require "util.timer"
local st = require "util.stanza"
local uuid = require "util.uuid".generate
module:log(LOGLEVEL, "loaded")

-- -----------------------------------------------------------------------------
local function _start_recording(room, session, occupant_jid)
    -- dont start recording if already triggered
    if room.is_recorder_triggered then
        return
    end

    -- get occupant current status
    local occupant = room:get_occupant_by_real_jid(occupant_jid)

    -- check recording permission
    if occupant == nil or occupant.role ~= "moderator" then
        return
    elseif
        session.jitsi_meet_context_features ~= nil and
        session.jitsi_meet_context_features["recording"] ~= true
    then
        return
    end

    -- start recording
    local iq = st.iq({
        type = "set",
        id = uuid() .. ":sendIQ",
        from = occupant_jid,
        to = room.jid .. "/focus"
        })
        :tag("jibri", {
            xmlns = "http://jitsi.org/protocol/jibri",
            action = "start",
            recording_mode = "file",
            app_data = '{"file_recording_metadata":{"share":true}}'})

    module:send(iq)
    room.is_recorder_triggered = true
end

-- -----------------------------------------------------------------------------
module:hook("muc-occupant-joined", function (event)
    local room = event.room
    local session = event.origin
    local occupant = event.occupant

    if is_healthcheck_room(room.jid) or is_admin(occupant.bare_jid) then
        return
    end

    -- wait for the affiliation to set then start recording if applicable
    timer.add_task(3, function()
        _start_recording(room, session, occupant.jid)
    end)
end)
