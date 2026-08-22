--- Collects final conference statistics and posts one JSON document to an HTTP endpoint.
---
--- Example Prosody configuration:
---
--- Component "cstatistics.meet.mydomain.com" "conference_statistics_component"
---     muc_component = "conference.meet.mydomain.com"
---     breakout_component = "breakout.meet.mydomain.com"
---
---     api_prefix = "https://example.com/api"
---     api_timeout = 10
---     api_retry_count = 5
---     api_retry_delay = 1
---
---     api_headers = {
---         ["Authorization"] = "Bearer TOKEN";
---     }
---
---     api_should_retry_for_code = function (code)
---         return code == 408 or code == 429 or code >= 500
---     end
---
---     -- Chat and poll content is not collected unless it is enabled here. Message,
---     -- poll and vote counts are always reported.
---     include_chat_content = false
---     include_poll_content = false
---
---     -- Optional safety limits. When a limit is reached, collection continues and
---     -- the resulting JSON contains a limit_reached entry in its errors array.
---     max_chat_messages = 2000
---     max_chat_message_length = 4096
---     max_tracked_connections = 10000
---     max_errors = 1000
---
--- The final URL is api_prefix .. "/events/conference/statistics".
--- This component must not be added to XMPP_MUC_MODULES.
--- With Jitsi Helm, put the configuration block in
--- prosody.extraEnvs.XMPP_CONFIGURATION and mount this file in a Prosody plugin path.
--- HTTP configuration intentionally follows the event_sync component model.
---
--- Runtime collection errors are isolated from the MUC hooks and included in the
--- final JSON. Delivery errors are included in the next retry. If every delivery
--- attempt fails, no remote statistics file can be created without a persistent
--- spool; the final failure is still written to the Prosody log.

local json = require "cjson.safe";
local http = require "net.http";
local jid = require "util.jid";
local socket = require "socket";
local timer = require "util.timer";
local util = module:require "util";

local is_admin = util.is_admin;
local is_focus = util.is_focus;
local is_healthcheck_room = util.is_healthcheck_room;
local is_jibri = util.is_jibri;
local is_sip_jigasi = util.is_sip_jigasi;
local is_transcriber = util.is_transcriber;
local process_host_module = util.process_host_module;

local NICK_NS = "http://jabber.org/protocol/nick";
local DISPLAY_NAME_NS = "http://jitsi.org/jitmeet/display-name";
local JITSI_MEET_NS = "http://jitsi.org/jitmeet";
local STATISTICS_PATH = "/events/conference/statistics";
local EMPTY_ARRAY_MARKER_KEY = "__jitsi_conference_statistics_empty_array__";
local EMPTY_ARRAY_MARKER_JSON = '{"' .. EMPTY_ARRAY_MARKER_KEY .. '":true}';
local EMPTY_ARRAY = { [EMPTY_ARRAY_MARKER_KEY] = true };

local main_muc_component_host = module:get_option_string("muc_component");
local breakout_muc_component_host = module:get_option_string("breakout_component");
local api_prefix = module:get_option_string("api_prefix");
local api_timeout = tonumber(module:get_option("api_timeout", 20)) or 20;
local api_retry_count = tonumber(module:get_option("api_retry_count", 3)) or 3;
local api_retry_delay = tonumber(module:get_option("api_retry_delay", 1)) or 1;
local configured_api_headers = module:get_option("api_headers", {});
local include_chat_content = module:get_option_boolean("include_chat_content", false);
local include_poll_content = module:get_option_boolean("include_poll_content", false);
local max_chat_messages = tonumber(module:get_option("max_chat_messages", 2000)) or 2000;
local max_chat_message_length = tonumber(module:get_option("max_chat_message_length", 4096)) or 4096;
local max_tracked_connections = tonumber(module:get_option("max_tracked_connections", 10000)) or 10000;
local max_errors = tonumber(module:get_option("max_errors", 1000)) or 1000;

local function default_should_retry_for_code(code)
    return code == 408 or code == 429 or code >= 500;
end

local api_should_retry_for_code = module:get_option(
    "api_should_retry_for_code",
    default_should_retry_for_code);

api_timeout = math.max(1, api_timeout);
api_retry_count = math.max(0, math.floor(api_retry_count));
api_retry_delay = math.max(0, api_retry_delay);
max_chat_messages = math.max(0, math.floor(max_chat_messages));
max_chat_message_length = math.max(1, math.floor(max_chat_message_length));
max_tracked_connections = math.max(1, math.floor(max_tracked_connections));
max_errors = math.max(1, math.floor(max_errors));

if not main_muc_component_host or main_muc_component_host == "" then
    module:log("error", "muc_component is not configured; disabling %s", module:get_name());
    return;
end

if not breakout_muc_component_host or breakout_muc_component_host == "" then
    module:log("error", "breakout_component is not configured; disabling %s", module:get_name());
    return;
end

if not api_prefix or api_prefix == "" then
    module:log("error", "api_prefix is not configured; disabling %s", module:get_name());
    return;
end

if type(configured_api_headers) ~= "table" then
    module:log("error", "api_headers must be a table; ignoring configured headers");
    configured_api_headers = {};
end

if type(api_should_retry_for_code) ~= "function" then
    module:log("error", "api_should_retry_for_code must be a function; using the default predicate");
    api_should_retry_for_code = default_should_retry_for_code;
end

local api_url = api_prefix .. STATISTICS_PATH;
local base_http_headers = {
    ["Content-Type"] = "application/json";
    ["User-Agent"] = "Prosody (" .. prosody.version .. "; " .. prosody.platform .. ")";
};

for key, value in pairs(configured_api_headers) do
    if type(key) == "string" and (type(value) == "string" or type(value) == "number") then
        base_http_headers[key] = tostring(value);
    else
        module:log("error", "Ignoring invalid api_headers entry");
    end
end

-- meetingId can be replaced by Jicofo after room creation, so it is an alias,
-- not the primary in-memory identity of a logical conference.
local meetings_by_id = {};
local meetings_by_main_room_jid = {};
local room_to_meeting = setmetatable({}, { __mode = "k" });
local room_to_record = setmetatable({}, { __mode = "k" });
local pending_component_errors = {};
local attached_hosts = {};
local main_muc_service;
local sequence = 0;

local function now_ms()
    return math.floor(socket.gettime() * 1000);
end

local function next_sequence()
    sequence = sequence + 1;
    return sequence;
end

-- Truncating in the middle of a multi-byte UTF-8 sequence would leave an invalid
-- byte sequence in the document, which the endpoint may reject as a whole. Drop
-- back over trailing continuation bytes (10xxxxxx) so only whole characters are kept.
local function truncate_at_character_boundary(text, maximum_length)
    local cut = maximum_length;
    while cut > 0 do
        local next_byte = text:byte(cut + 1);
        if not next_byte or next_byte < 0x80 or next_byte >= 0xc0 then
            break;
        end
        cut = cut - 1;
    end
    return text:sub(1, cut);
end

local function safe_string(value, maximum_length)
    if value == nil then
        return nil;
    end

    local value_type = type(value);
    if value_type ~= "string" and value_type ~= "number" and value_type ~= "boolean" then
        return nil;
    end

    local output = tostring(value);
    if maximum_length and #output > maximum_length then
        return truncate_at_character_boundary(output, maximum_length);
    end
    return output;
end

local function copy_context(context)
    if type(context) ~= "table" then
        return nil;
    end

    local output = {};
    for key, value in pairs(context) do
        local safe_key = safe_string(key, 64);
        local safe_value = safe_string(value, 512);
        if safe_key and safe_value then
            output[safe_key] = safe_value;
        end
    end

    if next(output) == nil then
        return nil;
    end
    return output;
end

local function error_key(code, stage, message, context)
    return table.concat({
        code or "unknown";
        stage or "unknown";
        message or "";
        context and context.room_jid or "";
        context and context.participant_id or "";
    }, "\31");
end

local function append_error(meeting, code, stage, message, context, timestamp)
    if not meeting then
        return;
    end

    local occurred_at_ms = timestamp or now_ms();
    local safe_code = safe_string(code, 128) or "unknown_error";
    local safe_stage = safe_string(stage, 128) or "unknown";
    local safe_message = safe_string(message, 2048) or "Unknown plugin error";
    local safe_context = copy_context(context);
    local key = error_key(safe_code, safe_stage, safe_message, safe_context);
    local existing = meeting.error_index[key];

    if existing then
        existing.count = existing.count + 1;
        existing.last_at_ms = occurred_at_ms;
        if safe_context then
            existing.last_context = safe_context;
        end
        return;
    end

    if #meeting.errors >= max_errors then
        meeting.errors_dropped = meeting.errors_dropped + 1;
        return;
    end

    local item = {
        code = safe_code;
        stage = safe_stage;
        message = safe_message;
        first_at_ms = occurred_at_ms;
        last_at_ms = occurred_at_ms;
        count = 1;
    };
    if safe_context then
        item.context = safe_context;
    end

    table.insert(meeting.errors, item);
    meeting.error_index[key] = item;
end

local function append_pending_error(code, stage, message, context)
    if #pending_component_errors >= max_errors then
        return;
    end
    table.insert(pending_component_errors, {
        code = code;
        stage = stage;
        message = message;
        context = copy_context(context);
        timestamp = now_ms();
    });
end

local function find_meeting_for_event(event)
    local room = event and event.room;
    local meeting = room and room_to_meeting[room];
    if meeting then
        return meeting;
    end

    if room and room.jid and meetings_by_main_room_jid[room.jid] then
        return meetings_by_main_room_jid[room.jid];
    end

    local meeting_id = room and room._data and room._data.meetingId;
    if meeting_id then
        return meetings_by_id[tostring(meeting_id)];
    end
    return nil;
end

local function record_runtime_error(event, stage, message)
    local context = {};
    if event and event.room then
        context.room_jid = event.room.jid;
    end
    if event and event.occupant then
        context.participant_id = jid.resource(event.occupant.nick or "")
            or jid.resource(event.occupant.jid or "");
    end

    local safe_message = safe_string(message, 4096) or "Unknown unhandled error";
    module:log("error", "Isolated conference statistics error in %s: %s", stage, safe_message);

    local meeting = find_meeting_for_event(event);
    if meeting then
        append_error(meeting, "unhandled_exception", stage, safe_message, context);
    else
        append_pending_error("unhandled_exception", stage, safe_message, context);
    end
end

local function traceback_error(error_value)
    local message = safe_string(error_value, 2048) or "Unknown Lua error";
    if debug and debug.traceback then
        return debug.traceback(message, 2);
    end
    return message;
end

local function isolated_handler(stage, handler)
    return function(event)
        local ok, error_message = xpcall(function()
            handler(event);
        end, traceback_error);

        if not ok then
            local recorded = pcall(record_runtime_error, event, stage, error_message);
            if not recorded then
                module:log("error", "Unable to record isolated conference statistics error in %s", stage);
            end
        end

        -- Never stop or modify the event processing chain.
        return nil;
    end;
end

local function register_meeting_id(meeting, meeting_id)
    local normalized_id = safe_string(meeting_id, 512);
    if not normalized_id or normalized_id == "" then
        return false;
    end

    local existing = meetings_by_id[normalized_id];
    if existing and existing ~= meeting then
        append_error(
            meeting,
            "meeting_id_collision",
            "room_identity",
            "meetingId is already associated with another active conference",
            { meeting_id = normalized_id; room_jid = meeting.main_room_jid });
        return false;
    end

    meetings_by_id[normalized_id] = meeting;
    meeting.meeting_id_aliases[normalized_id] = true;
    meeting.meeting_id = normalized_id;
    return true;
end

local function register_main_room(meeting, main_room)
    if not main_room or not main_room.jid then
        return false;
    end

    if meeting.main_room_jid and meeting.main_room_jid ~= main_room.jid then
        append_error(
            meeting,
            "main_room_mismatch",
            "room_identity",
            "A conference cannot be associated with two different main room JIDs",
            { room_jid = main_room.jid; expected_room_jid = meeting.main_room_jid });
        return false;
    end

    local existing = meetings_by_main_room_jid[main_room.jid];
    if existing and existing ~= meeting then
        append_error(
            meeting,
            "main_room_collision",
            "room_identity",
            "Main room JID is already associated with another active conference",
            { room_jid = main_room.jid });
        return false;
    end

    meetings_by_main_room_jid[main_room.jid] = meeting;
    meeting.main_room = main_room;
    meeting.main_room_jid = main_room.jid;
    return true;
end

local function read_room_meeting_id(room)
    local meeting_id = room and room._data and room._data.meetingId;
    return safe_string(meeting_id, 512);
end

local function new_meeting(meeting_id, main_room, started_at_ms)
    local meeting = {
        meeting_id = nil;
        meeting_id_aliases = {};
        started_at_ms = started_at_ms;
        ended_at_ms = nil;
        main_room = nil;
        main_room_jid = nil;
        main_room_ended = false;
        active_room_count = 0;
        rooms_by_jid = {};
        participants_by_id = {};
        endpoint_to_participant = {};
        chat = {};
        seen_chat = {};
        chat_message_count = 0;
        polls = {};
        poll_count = 0;
        poll_vote_count = 0;
        errors = {};
        error_index = {};
        errors_dropped = 0;
        connection_count = 0;
        finalized = false;
        delivery_finished = false;
    };

    for _, item in ipairs(pending_component_errors) do
        append_error(meeting, item.code, item.stage, item.message, item.context, item.timestamp);
    end
    pending_component_errors = {};

    register_main_room(meeting, main_room);
    register_meeting_id(meeting, meeting_id);
    return meeting;
end

local function get_main_room_for_breakout(breakout_room)
    if breakout_room.main_room then
        return breakout_room.main_room;
    end

    if breakout_room._data and breakout_room._data.main_room then
        return breakout_room._data.main_room;
    end

    if not main_muc_service then
        return nil;
    end

    for room in main_muc_service.each_room() do
        if room._data and room._data.breakout_rooms
            and room._data.breakout_rooms[breakout_room.jid] then
            -- Cache outside _data so room persistence never serializes an object graph.
            breakout_room.main_room = room;
            return room;
        end
    end
    return nil;
end

local function resolve_meeting_context(room, is_breakout)
    if not is_breakout then
        return room, read_room_meeting_id(room);
    end

    local main_room = get_main_room_for_breakout(room);
    local meeting_id = read_room_meeting_id(main_room);
    if meeting_id then
        return main_room, meeting_id;
    end

    -- Jitsi speakerstats sets sessionId on a breakout room to the main room's
    -- meetingId. It is useful only as a compatibility fallback because it can
    -- have been captured before Jicofo replaced the main room meetingId.
    local speakerstats_meeting_id = room.speakerStats and room.speakerStats.sessionId;
    return main_room, safe_string(speakerstats_meeting_id, 512);
end

local function refresh_room_identity(meeting, room_record, room)
    if room_record.is_breakout then
        local breakout_meeting_id = read_room_meeting_id(room);
        if breakout_meeting_id and breakout_meeting_id ~= "" then
            room_record.breakout_meeting_id = breakout_meeting_id;
        end
        return;
    end

    register_main_room(meeting, room);
    register_meeting_id(meeting, read_room_meeting_id(room));
end

local function track_room(room, is_breakout)
    if not room or is_healthcheck_room(room.jid) then
        return nil, nil;
    end

    local existing = room_to_record[room];
    if existing then
        return room_to_meeting[room], existing;
    end

    local started_at_ms = now_ms();
    local main_room, meeting_id = resolve_meeting_context(room, is_breakout);
    if not meeting_id then
        append_pending_error(
            "meeting_id_unavailable",
            "room_created",
            "Unable to resolve meetingId for room",
            { room_jid = room.jid });
        module:log("error", "Unable to resolve meetingId for room %s", room.jid);
        return nil, nil;
    end

    local main_room_jid = main_room and main_room.jid;
    local meeting_by_main_room = main_room_jid and meetings_by_main_room_jid[main_room_jid];
    local meeting_by_id = meetings_by_id[meeting_id];
    if meeting_by_main_room and meeting_by_id and meeting_by_main_room ~= meeting_by_id then
        append_error(
            meeting_by_main_room,
            "meeting_identity_conflict",
            "room_identity",
            "Main room JID and meetingId resolve to different active conferences",
            { room_jid = main_room_jid; meeting_id = meeting_id });
        return nil, nil;
    end

    local meeting = meeting_by_main_room or meeting_by_id;
    if meeting and main_room_jid and meeting.main_room_jid
        and meeting.main_room_jid ~= main_room_jid then
        append_error(
            meeting,
            "main_room_mismatch",
            "room_identity",
            "meetingId resolved to a conference with a different main room JID",
            { room_jid = main_room_jid; expected_room_jid = meeting.main_room_jid });
        return nil, nil;
    end

    if not meeting then
        meeting = new_meeting(meeting_id, main_room, started_at_ms);
    elseif meeting.finalized then
        append_error(
            meeting,
            "room_after_finalization",
            "room_created",
            "A room appeared after conference finalization started",
            { room_jid = room.jid });
        return nil, nil;
    end

    if main_room and not register_main_room(meeting, main_room) then
        return nil, nil;
    end
    if main_room then
        register_meeting_id(meeting, read_room_meeting_id(main_room) or meeting_id);
    elseif not meeting.meeting_id then
        register_meeting_id(meeting, meeting_id);
    end

    local room_record = {
        jid = room.jid;
        room_id = jid.node(room.jid) or room.jid;
        is_breakout = is_breakout;
        breakout_meeting_id = nil;
        started_at_ms = started_at_ms;
        ended_at_ms = nil;
        destroyed = false;
        chat_message_count = 0;
        poll_count = 0;
        poll_vote_count = 0;
        active_by_real_jid = {};
        active_by_nick = {};
    };
    refresh_room_identity(meeting, room_record, room);

    meeting.rooms_by_jid[room.jid] = room_record;
    meeting.active_room_count = meeting.active_room_count + 1;
    meeting.started_at_ms = math.min(meeting.started_at_ms, started_at_ms);

    room_to_meeting[room] = meeting;
    room_to_record[room] = room_record;
    module:log("debug", "Tracking room %s for meeting %s", room.jid, meeting.meeting_id);
    return meeting, room_record;
end

local function get_presence_child_text(stanza, child_name, namespace)
    if not stanza then
        return nil;
    end

    local child = namespace and stanza:get_child(child_name, namespace) or stanza:get_child(child_name);
    if not child and namespace then
        child = stanza:get_child(child_name);
    end
    return child and child:get_text() or nil;
end

local function get_display_name(occupant, stanza, context_user)
    local context_name = context_user and safe_string(context_user.name, 512);
    if context_name and context_name ~= "" then
        return context_name;
    end

    local presence = stanza;
    if not presence and occupant and occupant.get_presence then
        presence = occupant:get_presence();
    end

    return get_presence_child_text(presence, "nick", NICK_NS)
        or get_presence_child_text(presence, "display-name", DISPLAY_NAME_NS)
        or get_presence_child_text(presence, "display-name");
end

local function is_system_occupant(occupant)
    if not occupant then
        return true;
    end

    local real_jid = occupant.jid or occupant.bare_jid or "";
    local nick = occupant.nick or "";
    if is_focus(nick) or jid.node(real_jid) == "focus" then
        return true;
    end
    if is_admin(occupant.bare_jid or real_jid) then
        return true;
    end
    if is_transcriber(real_jid) or is_jibri(occupant) then
        return true;
    end

    local presence = occupant.get_presence and occupant:get_presence() or nil;
    return is_sip_jigasi(presence) and true or false;
end

local function new_connection_metric_state()
    return {
        known = false;
        active = false;
    };
end

local function new_aggregate_metric_state()
    return {
        active_count = 0;
        started_at_ms = nil;
        total_ms = 0;
        enable_count = 0;
        disable_count = 0;
    };
end

local function activate_aggregate_metric(metric, timestamp, count_transition)
    local was_active = metric.active_count > 0;
    metric.active_count = metric.active_count + 1;
    if was_active then
        return;
    end

    metric.started_at_ms = timestamp;
    if count_transition then
        metric.enable_count = metric.enable_count + 1;
    end
end

local function deactivate_aggregate_metric(metric, timestamp, count_transition)
    if metric.active_count <= 0 then
        return;
    end

    metric.active_count = metric.active_count - 1;
    if metric.active_count > 0 then
        return;
    end

    local started_at_ms = metric.started_at_ms or timestamp;
    metric.total_ms = metric.total_ms + math.max(0, timestamp - started_at_ms);
    metric.started_at_ms = nil;
    if count_transition then
        metric.disable_count = metric.disable_count + 1;
    end
end

local function set_connection_metric_state(
        aggregate_metric,
        connection_metric,
        enabled,
        timestamp,
        count_transition)
    if enabled == nil then
        return;
    end

    if not connection_metric.known then
        connection_metric.known = true;
        connection_metric.active = enabled;
        if enabled then
            activate_aggregate_metric(aggregate_metric, timestamp, false);
        end
        return;
    end

    if connection_metric.active == enabled then
        return;
    end

    connection_metric.active = enabled;
    if enabled then
        activate_aggregate_metric(aggregate_metric, timestamp, count_transition);
    else
        deactivate_aggregate_metric(aggregate_metric, timestamp, count_transition);
    end
end

local function close_connection_metric_state(aggregate_metric, connection_metric, timestamp)
    if connection_metric.known and connection_metric.active then
        connection_metric.active = false;
        deactivate_aggregate_metric(aggregate_metric, timestamp, false);
    end
end

local function aggregate_metric_total_ms(metric, timestamp)
    local total_ms = metric.total_ms;
    if metric.active_count > 0 then
        total_ms = total_ms + math.max(0, timestamp - (metric.started_at_ms or timestamp));
    end
    return math.floor(math.max(0, total_ms));
end

local function parse_boolean(value)
    if value == nil then
        return nil;
    end
    if value == true or value == "true" or value == "1" or value == 1 then
        return true;
    end
    if value == false or value == "false" or value == "0" or value == 0 then
        return false;
    end
    return nil;
end

local function source_owner_and_media_type(source_name)
    if type(source_name) ~= "string" then
        return nil, nil;
    end

    local owner, media_type = source_name:match("^(.+)%-([av])%d+$");
    if owner then
        return owner, media_type;
    end
    return source_name:match("^(.+)%-([av])%d+%.[^%.]+$");
end

local function is_desktop_video_type(video_type)
    if type(video_type) ~= "string" then
        return false;
    end
    local normalized = video_type:lower();
    return normalized == "screen"
        or normalized == "screenshare"
        or normalized:sub(1, 7) == "desktop";
end

local function parse_source_info(meeting, room_record, connection, source_info)
    local source_info_text = source_info and source_info:get_text();
    if not source_info_text then
        append_error(
            meeting,
            "invalid_source_info",
            "presence",
            "SourceInfo element has no JSON text",
            { room_jid = room_record.jid; participant_id = connection.participant_id });
        return nil, nil, nil;
    end

    local decoded, decode_error = json.decode(source_info_text);
    if type(decoded) ~= "table" then
        append_error(
            meeting,
            "invalid_source_info",
            "presence",
            decode_error or "SourceInfo is not a JSON object",
            { room_jid = room_record.jid; participant_id = connection.participant_id });
        return nil, nil, nil;
    end

    local microphone_enabled = false;
    local camera_enabled = false;
    local screenshare_enabled = false;

    for source_name, source_state in pairs(decoded) do
        local owner, media_type = source_owner_and_media_type(source_name);
        if owner ~= connection.endpoint_id then
            append_error(
                meeting,
                "foreign_source_info",
                "presence",
                "Ignoring SourceInfo entry not owned by the participant endpoint",
                { room_jid = room_record.jid; participant_id = connection.participant_id });
        elseif type(source_state) ~= "table" then
            append_error(
                meeting,
                "invalid_source_state",
                "presence",
                "Ignoring a non-object SourceInfo source state",
                { room_jid = room_record.jid; participant_id = connection.participant_id });
        else
            local muted = parse_boolean(source_state.muted);
            if muted == nil then
                muted = false;
            end

            if media_type == "a" and not muted then
                microphone_enabled = true;
            elseif media_type == "v" and not muted then
                if is_desktop_video_type(source_state.videoType) then
                    screenshare_enabled = true;
                else
                    camera_enabled = true;
                end
            end
        end
    end

    return microphone_enabled, camera_enabled, screenshare_enabled;
end

local function parse_legacy_media_state(stanza)
    local audio_muted_text = get_presence_child_text(stanza, "audiomuted", JITSI_MEET_NS)
        or get_presence_child_text(stanza, "audiomuted");
    local video_muted_text = get_presence_child_text(stanza, "videomuted", JITSI_MEET_NS)
        or get_presence_child_text(stanza, "videomuted");
    local video_type = get_presence_child_text(stanza, "videoType", JITSI_MEET_NS)
        or get_presence_child_text(stanza, "videoType");

    local audio_muted = parse_boolean(audio_muted_text);
    local video_muted = parse_boolean(video_muted_text);
    local microphone_enabled;
    local camera_enabled;
    local screenshare_enabled;

    if audio_muted ~= nil then
        microphone_enabled = not audio_muted;
    end

    if video_muted ~= nil then
        if is_desktop_video_type(video_type) then
            camera_enabled = false;
            screenshare_enabled = not video_muted;
        else
            camera_enabled = not video_muted;
            screenshare_enabled = false;
        end
    end

    return microphone_enabled, camera_enabled, screenshare_enabled;
end

local function apply_presence_state(
        meeting,
        room_record,
        connection,
        stanza,
        timestamp,
        count_transitions)
    if not stanza or stanza.attr.type == "unavailable" or stanza.attr.type == "error" then
        return;
    end

    local source_info = stanza:get_child("SourceInfo")
        or stanza:get_child("SourceInfo", JITSI_MEET_NS);
    local microphone_enabled;
    local camera_enabled;
    local screenshare_enabled;

    if source_info then
        microphone_enabled, camera_enabled, screenshare_enabled
            = parse_source_info(meeting, room_record, connection, source_info);
    else
        microphone_enabled, camera_enabled, screenshare_enabled = parse_legacy_media_state(stanza);
    end

    local participant = meeting.participants_by_id[connection.participant_id];
    if not participant then
        append_error(
            meeting,
            "participant_missing",
            "presence",
            "Participant aggregate is unavailable for an active connection",
            { room_jid = room_record.jid; participant_id = connection.participant_id });
        return;
    end

    set_connection_metric_state(
        participant.microphone,
        connection.microphone,
        microphone_enabled,
        timestamp,
        count_transitions);
    set_connection_metric_state(
        participant.camera,
        connection.camera,
        camera_enabled,
        timestamp,
        count_transitions);
    set_connection_metric_state(
        participant.screenshare,
        connection.screenshare,
        screenshare_enabled,
        timestamp,
        count_transitions);
end

local function snapshot_dominant_speaker(meeting, room, room_record, connection, timestamp)
    if not room.speakerStats then
        append_error(
            meeting,
            "speakerstats_unavailable",
            "speakerstats",
            "room.speakerStats is unavailable",
            { room_jid = room_record.jid; participant_id = connection.participant_id });
        return;
    end

    local stats = room.speakerStats[connection.real_jid];
    if type(stats) ~= "table" then
        append_error(
            meeting,
            "speakerstats_entry_missing",
            "speakerstats",
            "No speakerstats entry exists for the participant connection",
            { room_jid = room_record.jid; participant_id = connection.participant_id });
        return;
    end

    local total = tonumber(stats.totalDominantSpeakerTime) or 0;
    if stats._isDominantSpeaker and not stats._isSilent and tonumber(stats._dominantSpeakerStart) then
        total = total + math.max(0, timestamp - tonumber(stats._dominantSpeakerStart));
    end
    connection.dominant_speaker_ms = math.max(
        connection.dominant_speaker_ms or 0,
        math.floor(math.max(0, total)));
end

local function close_connection(meeting, room, room_record, connection, timestamp)
    if connection.left_at_ms then
        return;
    end

    local ended_at_ms = math.max(connection.joined_at_ms, timestamp);
    snapshot_dominant_speaker(meeting, room, room_record, connection, ended_at_ms);
    local participant = meeting.participants_by_id[connection.participant_id];
    if participant then
        close_connection_metric_state(participant.microphone, connection.microphone, ended_at_ms);
        close_connection_metric_state(participant.camera, connection.camera, ended_at_ms);
        close_connection_metric_state(participant.screenshare, connection.screenshare, ended_at_ms);
        deactivate_aggregate_metric(participant.presence, ended_at_ms, false);
        participant.dominant_speaker_ms = participant.dominant_speaker_ms
            + (connection.dominant_speaker_ms or 0);
    else
        append_error(
            meeting,
            "participant_missing",
            "occupant_leaving",
            "Participant aggregate is unavailable while closing a connection",
            { room_jid = room_record.jid; participant_id = connection.participant_id });
    end
    connection.left_at_ms = ended_at_ms;

    if room_record.active_by_real_jid[connection.real_jid] == connection then
        room_record.active_by_real_jid[connection.real_jid] = nil;
    end
    if room_record.active_by_nick[connection.occupant_nick] == connection then
        room_record.active_by_nick[connection.occupant_nick] = nil;
    end
end

local function get_or_create_participant(meeting, participant_id, id_source, display_name, email)
    local participant = meeting.participants_by_id[participant_id];
    if not participant then
        participant = {
            participant_id = participant_id;
            participant_id_source = id_source;
            display_name = display_name;
            email = email;
            endpoint_ids = {};
            has_joined = false;
            rejoin_count = 0;
            presence = new_aggregate_metric_state();
            microphone = new_aggregate_metric_state();
            camera = new_aggregate_metric_state();
            screenshare = new_aggregate_metric_state();
            dominant_speaker_ms = 0;
            chat_message_count = 0;
            poll_vote_count = 0;
        };
        meeting.participants_by_id[participant_id] = participant;
    else
        if display_name and display_name ~= "" then
            participant.display_name = display_name;
        end
        if email and email ~= "" then
            participant.email = email;
        end
    end
    return participant;
end

local function handle_occupant_joined(event)
    local room, occupant = event.room, event.occupant;
    if not room or is_healthcheck_room(room.jid) or is_system_occupant(occupant) then
        return;
    end

    local meeting = room_to_meeting[room];
    local room_record = room_to_record[room];
    if not meeting or not room_record then
        return;
    end

    if meeting.connection_count >= max_tracked_connections then
        append_error(
            meeting,
            "limit_reached",
            "occupant_joined",
            "max_tracked_connections was reached; connection was not collected",
            { room_jid = room.jid });
        return;
    end

    local joined_at_ms = now_ms();
    local real_jid = safe_string(occupant.jid, 1024) or "unknown-real-jid";
    local occupant_nick = safe_string(occupant.nick, 1024) or "unknown-occupant-nick";
    local endpoint_id = jid.resource(occupant_nick) or jid.resource(real_jid) or real_jid;
    local context_user = event.origin and event.origin.jitsi_meet_context_user or nil;
    local jwt_user_id = context_user and safe_string(context_user.id, 512);
    local participant_id = jwt_user_id and jwt_user_id ~= "" and jwt_user_id or endpoint_id;
    local id_source = jwt_user_id and jwt_user_id ~= "" and "jwt" or "endpoint";
    local display_name = get_display_name(occupant, event.stanza, context_user);
    local email = context_user and safe_string(context_user.email, 512) or nil;

    local previous = room_record.active_by_real_jid[real_jid];
    if previous then
        append_error(
            meeting,
            "duplicate_active_connection",
            "occupant_joined",
            "An active connection with the same real JID was replaced",
            { room_jid = room.jid; participant_id = previous.participant_id });
        close_connection(meeting, room, room_record, previous, joined_at_ms);
    end

    local participant = get_or_create_participant(
        meeting,
        participant_id,
        id_source,
        display_name,
        email);
    local endpoint_seen_before = participant.endpoint_ids[endpoint_id] and true or false;
    if participant.presence.active_count == 0
        and participant.has_joined
        and not endpoint_seen_before then
        participant.rejoin_count = participant.rejoin_count + 1;
    end
    participant.has_joined = true;
    participant.endpoint_ids[endpoint_id] = true;
    meeting.endpoint_to_participant[endpoint_id] = participant_id;
    activate_aggregate_metric(participant.presence, joined_at_ms, false);

    local connection = {
        participant_id = participant_id;
        endpoint_id = endpoint_id;
        real_jid = real_jid;
        occupant_nick = occupant_nick;
        room_jid = room.jid;
        joined_at_ms = joined_at_ms;
        left_at_ms = nil;
        dominant_speaker_ms = 0;
        microphone = new_connection_metric_state();
        camera = new_connection_metric_state();
        screenshare = new_connection_metric_state();
    };

    room_record.active_by_real_jid[real_jid] = connection;
    room_record.active_by_nick[occupant_nick] = connection;
    meeting.connection_count = meeting.connection_count + 1;

    local presence = event.stanza or (occupant.get_presence and occupant:get_presence());
    apply_presence_state(meeting, room_record, connection, presence, joined_at_ms, false);
end

local function find_active_connection(room_record, occupant)
    if not room_record or not occupant then
        return nil;
    end
    return room_record.active_by_real_jid[occupant.jid]
        or room_record.active_by_nick[occupant.nick];
end

local function handle_presence(event)
    local room, occupant, stanza = event.room, event.occupant, event.stanza;
    if not room or not occupant or not stanza or is_system_occupant(occupant) then
        return;
    end

    local meeting = room_to_meeting[room];
    local room_record = room_to_record[room];
    local connection = find_active_connection(room_record, occupant);
    if not meeting or not connection then
        return;
    end

    local participant = meeting.participants_by_id[connection.participant_id];
    local display_name = get_display_name(occupant, stanza, nil);
    if participant and display_name and display_name ~= "" then
        participant.display_name = display_name;
    end

    apply_presence_state(meeting, room_record, connection, stanza, now_ms(), true);
end

local function handle_occupant_leaving(event)
    local room, occupant = event.room, event.occupant;
    if not room or not occupant or is_system_occupant(occupant) then
        return;
    end

    local meeting = room_to_meeting[room];
    local room_record = room_to_record[room];
    local connection = find_active_connection(room_record, occupant);
    if not meeting or not connection then
        return;
    end

    local participant = meeting.participants_by_id[connection.participant_id];
    local display_name = get_display_name(occupant, nil, nil);
    if participant and display_name and display_name ~= "" then
        participant.display_name = display_name;
    end

    close_connection(meeting, room, room_record, connection, now_ms());
end

local function handle_groupchat(event)
    local room, stanza = event.room, event.stanza;
    if not room or not stanza or stanza.attr.type ~= "groupchat" then
        return;
    end

    local body = stanza:get_child_text("body");
    if body == nil then
        return;
    end

    local meeting = room_to_meeting[room];
    local room_record = room_to_record[room];
    if not meeting or not room_record then
        return;
    end

    if meeting.chat_message_count >= max_chat_messages then
        append_error(
            meeting,
            "limit_reached",
            "groupchat",
            "max_chat_messages was reached; message was not collected",
            { room_jid = room.jid });
        return;
    end

    local from = safe_string(stanza.attr.from, 1024) or "";
    local sender_endpoint_id = jid.resource(from);
    if sender_endpoint_id == "focus" then
        return;
    end

    local occupant = room:get_occupant_by_nick(from);
    if occupant and is_system_occupant(occupant) then
        return;
    end

    local connection = occupant and find_active_connection(room_record, occupant)
        or room_record.active_by_nick[from];
    if connection then
        sender_endpoint_id = connection.endpoint_id;
    end

    local stanza_id = safe_string(stanza.attr.id, 512);
    local deduplication_key = stanza_id and table.concat({ room.jid; from; stanza_id }, "\31") or nil;
    if deduplication_key and meeting.seen_chat[deduplication_key] then
        return;
    end
    if deduplication_key then
        meeting.seen_chat[deduplication_key] = true;
    end

    local participant_id = connection and connection.participant_id
        or (sender_endpoint_id and meeting.endpoint_to_participant[sender_endpoint_id])
        or sender_endpoint_id;
    local sender = participant_id and meeting.participants_by_id[participant_id];

    meeting.chat_message_count = meeting.chat_message_count + 1;
    room_record.chat_message_count = room_record.chat_message_count + 1;
    if sender then
        sender.chat_message_count = sender.chat_message_count + 1;
    end

    if not include_chat_content then
        return;
    end

    local message_id = stanza_id or table.concat({
        meeting.meeting_id;
        "message";
        tostring(next_sequence());
    }, ":");
    local display_name = occupant and get_display_name(occupant, stanza, nil)
        or get_presence_child_text(stanza, "display-name", DISPLAY_NAME_NS)
        or get_presence_child_text(stanza, "display-name")
        or get_presence_child_text(stanza, "nick", NICK_NS);
    if (not display_name or display_name == "") and sender then
        display_name = sender.display_name;
    end

    table.insert(meeting.chat, {
        message_id = message_id;
        sent_at_ms = now_ms();
        room_id = room_record.room_id;
        room_jid = room_record.jid;
        sender_participant_id = participant_id;
        sender_endpoint_id = sender_endpoint_id;
        sender_display_name = display_name;
        body = safe_string(body, max_chat_message_length);
    });
end

local function count_poll_state(meeting, room_record, poll)
    meeting.poll_count = meeting.poll_count + 1;
    room_record.poll_count = room_record.poll_count + 1;

    for _, answer in ipairs(type(poll.answers) == "table" and poll.answers or {}) do
        if type(answer) == "table" and type(answer.voters) == "table" then
            for _, voter in ipairs(answer.voters) do
                if type(voter) == "table" then
                    meeting.poll_vote_count = meeting.poll_vote_count + 1;
                    room_record.poll_vote_count = room_record.poll_vote_count + 1;

                    local voter_id = safe_string(voter.id, 512);
                    local participant_id = voter_id and meeting.endpoint_to_participant[voter_id];
                    local participant = participant_id and meeting.participants_by_id[participant_id];
                    if participant then
                        participant.poll_vote_count = participant.poll_vote_count + 1;
                    end
                end
            end
        end
    end
end

local function snapshot_polls(meeting, room, room_record)
    if not room.polls then
        append_error(
            meeting,
            "polls_unavailable",
            "polls",
            "room.polls is unavailable",
            { room_jid = room_record.jid });
        return;
    end

    if type(room.polls.order) ~= "table" then
        append_error(
            meeting,
            "invalid_polls_state",
            "polls",
            "room.polls.order is not a table",
            { room_jid = room_record.jid });
        return;
    end

    for poll_index, poll in ipairs(room.polls.order) do
        if type(poll) ~= "table" then
            append_error(
                meeting,
                "invalid_poll",
                "polls",
                "Ignoring a non-object poll",
                { room_jid = room_record.jid });
        else
            count_poll_state(meeting, room_record, poll);

            if include_poll_content then
                local options = {};
                for option_index, answer in ipairs(type(poll.answers) == "table" and poll.answers or {}) do
                    local voters = {};
                    if type(answer) == "table" and type(answer.voters) == "table" then
                        for _, voter in ipairs(answer.voters) do
                            if type(voter) == "table" then
                                local voter_id = safe_string(voter.id, 512);
                                table.insert(voters, {
                                    voter_id = voter_id;
                                    participant_id = voter_id
                                        and meeting.endpoint_to_participant[voter_id] or nil;
                                    name = safe_string(voter.name, 512);
                                });
                            end
                        end
                    end

                    table.insert(options, {
                        option_index = option_index;
                        text = type(answer) == "table" and safe_string(answer.name, 4096) or nil;
                        voters = #voters == 0 and EMPTY_ARRAY or voters;
                    });
                end

                local creator_endpoint_id = safe_string(poll.senderId, 512);
                table.insert(meeting.polls, {
                    poll_id = safe_string(poll.pollId, 512) or tostring(poll_index);
                    room_id = room_record.room_id;
                    room_jid = room_record.jid;
                    creator_endpoint_id = creator_endpoint_id;
                    creator_participant_id = creator_endpoint_id
                        and meeting.endpoint_to_participant[creator_endpoint_id] or nil;
                    creator_name = safe_string(poll.senderName, 512);
                    question = safe_string(poll.question, 16384);
                    options = #options == 0 and EMPTY_ARRAY or options;
                });
            end
        end
    end
end

local function make_json_array(values)
    if #values == 0 then
        return EMPTY_ARRAY;
    end
    return values;
end

local function build_participant_output(participant, timestamp)
    local endpoint_ids = {};

    for endpoint_id in pairs(participant.endpoint_ids) do
        table.insert(endpoint_ids, endpoint_id);
    end
    table.sort(endpoint_ids);

    local presence_ms = aggregate_metric_total_ms(participant.presence, timestamp);

    return {
        participant_id = participant.participant_id;
        participant_id_source = participant.participant_id_source;
        display_name = participant.display_name;
        email = participant.email;
        endpoint_ids = make_json_array(endpoint_ids);
        presence_ms = presence_ms;
        rejoin_count = participant.rejoin_count;
        microphone_unmuted_ms = aggregate_metric_total_ms(participant.microphone, timestamp);
        microphone_unmute_count = participant.microphone.enable_count;
        microphone_mute_count = participant.microphone.disable_count;
        dominant_speaker_ms = math.min(math.floor(participant.dominant_speaker_ms), presence_ms);
        camera_enabled_ms = aggregate_metric_total_ms(participant.camera, timestamp);
        camera_enable_count = participant.camera.enable_count;
        camera_disable_count = participant.camera.disable_count;
        screenshare_enabled_ms = aggregate_metric_total_ms(participant.screenshare, timestamp);
        screenshare_start_count = participant.screenshare.enable_count;
        screenshare_stop_count = participant.screenshare.disable_count;
        chat_message_count = participant.chat_message_count;
        poll_vote_count = participant.poll_vote_count;
    };
end

local function copy_error_output(item)
    return {
        code = item.code;
        stage = item.stage;
        message = item.message;
        first_at_ms = item.first_at_ms;
        last_at_ms = item.last_at_ms;
        count = item.count;
        context = item.context;
        last_context = item.last_context;
    };
end

local function build_payload(meeting)
    local ended_at_ms = meeting.ended_at_ms or now_ms();
    local rooms = {};
    for _, room_record in pairs(meeting.rooms_by_jid) do
        local room_ended_at_ms = room_record.ended_at_ms
            or meeting.ended_at_ms
            or room_record.started_at_ms;
        local room_output = {
            room_id = room_record.room_id;
            jid = room_record.jid;
            is_breakout = room_record.is_breakout;
            started_at_ms = room_record.started_at_ms;
            ended_at_ms = room_ended_at_ms;
            duration_ms = math.max(0, room_ended_at_ms - room_record.started_at_ms);
            chat_message_count = room_record.chat_message_count;
            poll_count = room_record.poll_count;
            poll_vote_count = room_record.poll_vote_count;
        };
        if room_record.is_breakout then
            room_output.breakout_meeting_id = room_record.breakout_meeting_id;
            if not room_record.breakout_meeting_id then
                append_error(
                    meeting,
                    "breakout_meeting_id_unavailable",
                    "room_identity",
                    "Unable to resolve the breakout room meetingId",
                    { room_jid = room_record.jid });
            end
        end
        table.insert(rooms, room_output);
    end
    table.sort(rooms, function(left, right)
        if left.started_at_ms == right.started_at_ms then
            return left.jid < right.jid;
        end
        return left.started_at_ms < right.started_at_ms;
    end);

    local participants = {};
    for _, participant in pairs(meeting.participants_by_id) do
        table.insert(participants, build_participant_output(participant, ended_at_ms));
    end
    table.sort(participants, function(left, right)
        return left.participant_id < right.participant_id;
    end);

    local errors = {};
    for _, item in ipairs(meeting.errors) do
        table.insert(errors, copy_error_output(item));
    end

    return {
        schema = "jitsi-conference-statistics/v1";
        meeting_id = meeting.meeting_id;
        generated_at_ms = now_ms();
        collection_complete = #errors == 0 and meeting.errors_dropped == 0;
        errors_dropped = meeting.errors_dropped;
        conference = {
            main_room_jid = meeting.main_room_jid;
            started_at_ms = meeting.started_at_ms;
            ended_at_ms = ended_at_ms;
            duration_ms = math.max(0, ended_at_ms - meeting.started_at_ms);
            chat_message_count = meeting.chat_message_count;
            poll_count = meeting.poll_count;
            poll_vote_count = meeting.poll_vote_count;
        };
        rooms = make_json_array(rooms);
        participants = make_json_array(participants);
        chat = make_json_array(meeting.chat);
        polls = make_json_array(meeting.polls);
        errors = make_json_array(errors);
    };
end

local function finish_delivery(meeting, success)
    if meeting.delivery_finished then
        return;
    end
    meeting.delivery_finished = true;
    for meeting_id in pairs(meeting.meeting_id_aliases) do
        if meetings_by_id[meeting_id] == meeting then
            meetings_by_id[meeting_id] = nil;
        end
    end
    if meeting.main_room_jid and meetings_by_main_room_jid[meeting.main_room_jid] == meeting then
        meetings_by_main_room_jid[meeting.main_room_jid] = nil;
    end
    meeting.main_room = nil;

    if success then
        module:log("info", "Conference statistics delivered for meeting %s", meeting.meeting_id);
    else
        module:log(
            "error",
            "Conference statistics delivery exhausted for meeting %s; no persistent spool is configured",
            meeting.meeting_id);
    end
end

local send_meeting_attempt;

local function schedule_retry(meeting, retries_left, attempt, reason)
    if retries_left <= 0 then
        append_error(
            meeting,
            "delivery_exhausted",
            "delivery",
            "No HTTP delivery retries remain",
            { attempt = attempt; reason = reason });
        finish_delivery(meeting, false);
        return;
    end

    local scheduled, schedule_error = pcall(timer.add_task, api_retry_delay, function()
        local ok, error_message = xpcall(function()
            send_meeting_attempt(meeting, retries_left - 1, attempt + 1);
        end, traceback_error);
        if not ok then
            append_error(
                meeting,
                "retry_callback_failed",
                "delivery",
                error_message,
                { attempt = attempt + 1 });
            module:log("error", "Statistics retry callback failed: %s", error_message);
            finish_delivery(meeting, false);
        end
    end);

    if not scheduled then
        append_error(
            meeting,
            "retry_schedule_failed",
            "delivery",
            schedule_error,
            { attempt = attempt });
        finish_delivery(meeting, false);
    end
end

send_meeting_attempt = function(meeting, retries_left, attempt)
    if meeting.delivery_finished then
        return;
    end

    local payload;
    local payload_ok, payload_error = xpcall(function()
        payload = build_payload(meeting);
    end, traceback_error);
    if not payload_ok then
        append_error(meeting, "payload_build_failed", "delivery", payload_error, { attempt = attempt });
        schedule_retry(meeting, retries_left, attempt, "payload_build_failed");
        return;
    end

    local body, encode_error = json.encode(payload);
    if not body then
        append_error(
            meeting,
            "payload_encode_failed",
            "delivery",
            encode_error or "JSON encoding failed",
            { attempt = attempt });
        schedule_retry(meeting, retries_left, attempt, "payload_encode_failed");
        return;
    end
    body = body:gsub(EMPTY_ARRAY_MARKER_JSON, "[]");

    local headers = {};
    for key, value in pairs(base_http_headers) do
        headers[key] = value;
    end
    headers["Idempotency-Key"] = meeting.meeting_id;

    local completed = false;
    local request;
    local function handle_response(_, response_code)
        if completed or meeting.delivery_finished then
            return;
        end
        completed = true;

        local code = tonumber(response_code) or 0;
        if code >= 200 and code < 300 then
            finish_delivery(meeting, true);
            return;
        end

        append_error(
            meeting,
            code == 0 and "http_network_error" or "http_response_error",
            "delivery",
            code == 0 and "HTTP request failed without a response" or "Endpoint returned HTTP " .. code,
            { attempt = attempt; http_status = code });

        local should_retry = code == 0;
        if code ~= 0 then
            local predicate_ok, predicate_result = pcall(api_should_retry_for_code, code);
            if predicate_ok then
                should_retry = predicate_result and true or false;
            else
                append_error(
                    meeting,
                    "retry_predicate_failed",
                    "delivery",
                    predicate_result,
                    { attempt = attempt; http_status = code });
                should_retry = default_should_retry_for_code(code);
            end
        end

        if should_retry then
            schedule_retry(meeting, retries_left, attempt, "http_" .. tostring(code));
        else
            finish_delivery(meeting, false);
        end
    end

    local request_ok, request_or_error = pcall(http.request, api_url, {
        headers = headers;
        method = "POST";
        body = body;
    }, function(response_body, response_code)
        local callback_ok, callback_error = xpcall(function()
            handle_response(response_body, response_code);
        end, traceback_error);
        if not callback_ok then
            append_error(
                meeting,
                "http_callback_failed",
                "delivery",
                callback_error,
                { attempt = attempt });
            module:log("error", "Statistics HTTP callback failed: %s", callback_error);
            if not completed then
                completed = true;
                schedule_retry(meeting, retries_left, attempt, "http_callback_failed");
            end
        end
    end);

    if not request_ok or not request_or_error then
        completed = true;
        append_error(
            meeting,
            "http_request_failed",
            "delivery",
            request_ok and "net.http returned no request" or request_or_error,
            { attempt = attempt });
        schedule_retry(meeting, retries_left, attempt, "http_request_failed");
        return;
    end
    request = request_or_error;

    local timeout_ok, timeout_error = pcall(timer.add_task, api_timeout, function()
        local callback_ok, callback_error = xpcall(function()
            if completed or meeting.delivery_finished then
                return;
            end
            completed = true;
            pcall(http.destroy_request, request);
            append_error(
                meeting,
                "http_timeout",
                "delivery",
                "Endpoint did not respond before api_timeout",
                { attempt = attempt });
            schedule_retry(meeting, retries_left, attempt, "timeout");
        end, traceback_error);

        if not callback_ok then
            pcall(append_error,
                meeting,
                "timeout_callback_failed",
                "delivery",
                callback_error,
                { attempt = attempt });
            module:log("error", "Statistics timeout callback failed: %s", callback_error);
            if not meeting.delivery_finished then
                schedule_retry(meeting, retries_left, attempt, "timeout_callback_failed");
            end
        end
    end);

    if not timeout_ok then
        append_error(
            meeting,
            "timeout_schedule_failed",
            "delivery",
            timeout_error,
            { attempt = attempt });
        module:log("error", "Unable to schedule statistics HTTP timeout: %s", timeout_error);
        if not completed then
            completed = true;
            pcall(http.destroy_request, request);
            schedule_retry(meeting, retries_left, attempt, "timeout_schedule_failed");
        end
    end
end;

local function finalize_meeting_if_ready(meeting)
    if meeting.finalized or not meeting.main_room_ended or meeting.active_room_count > 0 then
        return;
    end

    if meeting.main_room then
        register_meeting_id(meeting, read_room_meeting_id(meeting.main_room));
    end
    meeting.finalized = true;
    meeting.ended_at_ms = meeting.ended_at_ms or now_ms();
    module:log("info", "Finalizing conference statistics for meeting %s", meeting.meeting_id);

    local ok, error_message = xpcall(function()
        send_meeting_attempt(meeting, api_retry_count, 1);
    end, traceback_error);
    if not ok then
        append_error(meeting, "delivery_start_failed", "delivery", error_message);
        module:log("error", "Unable to start statistics delivery: %s", error_message);
        finish_delivery(meeting, false);
    end
end

local function handle_room_destroyed(event)
    local room = event.room;
    local meeting = room and room_to_meeting[room];
    local room_record = room and room_to_record[room];
    if not meeting or not room_record or room_record.destroyed then
        return;
    end

    local destroyed_at_ms = now_ms();
    local active_connections = {};
    for _, connection in pairs(room_record.active_by_real_jid) do
        table.insert(active_connections, connection);
    end
    for _, connection in ipairs(active_connections) do
        close_connection(meeting, room, room_record, connection, destroyed_at_ms);
    end

    snapshot_polls(meeting, room, room_record);
    refresh_room_identity(meeting, room_record, room);
    room_record.destroyed = true;
    room_record.ended_at_ms = destroyed_at_ms;
    meeting.ended_at_ms = math.max(meeting.ended_at_ms or destroyed_at_ms, destroyed_at_ms);
    meeting.active_room_count = math.max(0, meeting.active_room_count - 1);
    if not room_record.is_breakout then
        meeting.main_room_ended = true;
        -- The final main meetingId was captured above; do not retain the whole
        -- destroyed MUC room object while breakout rooms finish or HTTP retries run.
        meeting.main_room = nil;
    end

    room_to_meeting[room] = nil;
    room_to_record[room] = nil;
    finalize_meeting_if_ready(meeting);
end

local function register_hook(host_module, event_name, handler, priority)
    local ok, error_message = pcall(function()
        host_module:hook(event_name, isolated_handler(event_name, handler), priority);
    end);
    if not ok then
        module:log("error", "Unable to register %s hook on %s: %s", event_name, host_module.host, error_message);
        append_pending_error(
            "hook_registration_failed",
            "initialization",
            error_message,
            { host = host_module.host; event = event_name });
    end
end

local function attach_muc_hooks(host_module, is_breakout)
    if attached_hosts[host_module.host] then
        return;
    end
    attached_hosts[host_module.host] = true;

    register_hook(host_module, "muc-room-created", function(event)
        track_room(event.room, is_breakout);
    end, -3);
    register_hook(host_module, "muc-occupant-joined", handle_occupant_joined, -3);
    register_hook(host_module, "muc-broadcast-presence", handle_presence, -3);
    register_hook(host_module, "muc-broadcast-message", handle_groupchat, 1);
    register_hook(host_module, "muc-occupant-pre-leave", handle_occupant_leaving, -3);
    register_hook(host_module, "muc-occupant-left", handle_occupant_leaving, -3);
    register_hook(host_module, "muc-room-destroyed", handle_room_destroyed, -3);
    module:log("info", "Conference statistics hooks attached to %s", host_module.host);
end

local function setup_host(host_module, host, is_breakout)
    local function attach_when_muc_is_ready()
        local host_data = prosody.hosts[host];
        local muc_module = host_data and host_data.modules and host_data.modules.muc;
        if not muc_module then
            return false;
        end
        if not is_breakout then
            main_muc_service = muc_module;
        end
        attach_muc_hooks(host_module, is_breakout);
        return true;
    end

    if attach_when_muc_is_ready() then
        return;
    end

    module:log("debug", "Waiting for the muc module on %s", host);
    prosody.hosts[host].events.add_handler("module-loaded", function(event)
        if event.module ~= "muc" then
            return;
        end
        local ok, error_message = xpcall(attach_when_muc_is_ready, traceback_error);
        if not ok then
            record_runtime_error(nil, "initialization", error_message);
        end
    end);
end

local function register_muc_component(component_host, is_breakout)
    local ok, error_message = xpcall(function()
        process_host_module(component_host, function(host_module, host)
            local setup_ok, setup_error = xpcall(function()
                setup_host(host_module, host, is_breakout);
            end, traceback_error);
            if not setup_ok then
                record_runtime_error(nil, "initialization", setup_error);
            end
        end);
    end, traceback_error);
    if not ok then
        record_runtime_error(nil, "initialization", error_message);
    end
end

register_muc_component(main_muc_component_host, false);
register_muc_component(breakout_muc_component_host, true);

module:log(
    "info",
    "Conference statistics component initialized for %s and %s; endpoint=%s",
    main_muc_component_host,
    breakout_muc_component_host,
    api_url);
