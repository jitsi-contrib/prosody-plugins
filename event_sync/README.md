# Event Sync

This prosody component sends HTTP POST request with JSON payload to external API when occupant or room events are triggered.

If JWT token auth is used, `name`, `email` and `id` from the user context is also included in the JSON
payload for occupant data.

## Events

### muc-room-created

When a room is created, `POST ${api_prefix}/events/room/created` is called with JSON payload containing:
* event_name
* room_name
* room_jid
* is_breakout
* breakout_room_id (only if is_breakout is true)
* created_at

Example:

```json
{
  "event_name": "muc-room-created",
  "room_name": "catchup",
  "room_jid": "catchup@conference.meet.mydomain.com",
  "is_breakout": false,
  "created_at": 1625823996
}
```

### muc-room-destroyed

When a room is destroyed, `POST ${api_prefix}/events/room/destroyed` is called with JSON payload containing:
* event_name
* room_name
* room_jid
* is_breakout
* breakout_room_id (only if is_breakout is true)
* created_at
* destroyed_at
* all_occupants (list of all occupants that has joined since room created)

Example:

```json
{
  "event_name": "muc-room-destroyed",
  "room_name": "catchup",
  "room_jid": "catchup@conference.meet.mydomain.com",
  "is_breakout": false,
  "created_at": 1625823996,
  "destroyed_at": 1625824035,
  "all_occupants": [
    {
      "name": "James Barrow",
      "email": "j.barrow@domain.com",
      "id": "00380324-a840-400d-880f-7ee0933b7556",
      "occupant_jid": "14f01c40-5195-4a4d-8efb-f58b49d18741@meet.mydomain.com/OWhl8jSh",
      "joined_at": 1625823996,
      "left_at": 1625824035
    }
  ]
}
```

### muc-occupant-joined

When an occupant joins, `POST ${api_prefix}/events/occupant/joined` is called with JSON payload containing:
* event_name
* room_name
* room_jid
* is_breakout
* breakout_room_id (only if is_breakout is true)
* occupant
    * occupant_jid
    * joined_at
    * name (if JWT token auth used. Taken from user context.)
    * email (if JWT token auth used. Taken from user context.)
    * id (if JWT token auth used. Taken from user context.)

Example:

```json
{
  "event_name": "muc-occupant-joined",
  "room_name": "catchup",
  "room_jid": "catchup@conference.meet.mydomain.com",
  "is_breakout": false,
  "occupant": {
    "name": "James Barrow",
    "email": "j.barrow@domain.com",
    "id": "00380324-a840-400d-880f-7ee0933b7556",
    "occupant_jid": "14f01c40-5195-4a4d-8efb-f58b49d18741@meet.mydomain.com/OWhl8jSh",
    "joined_at": 1625823996
  }
}
```

### muc-occupant-left

When an occupant leaves, `POST ${api_prefix}/events/occupant/left` is called with JSON payload containing:
* event_name
* room_name
* room_jid
* is_breakout
* breakout_room_id (only if is_breakout is true)
* occupant
    * occupant_jid
    * joined_at
    * left_at
    * name (if JWT token auth used. Taken from user context.)
    * email (if JWT token auth used. Taken from user context.)
    * id (if JWT token auth used. Taken from user context.)

Example:

```json
{
  "event_name": "muc-occupant-left",
  "room_name": "catchup",
  "room_jid": "catchup@conference.meet.mydomain.com",
  "is_breakout": false,
  "occupant": {
    "name": "James Barrow",
    "email": "j.barrow@domain.com",
    "id": "00380324-a840-400d-880f-7ee0933b7556",
    "occupant_jid": "14f01c40-5195-4a4d-8efb-f58b49d18741@meet.mydomain.com/OWhl8jSh",
    "joined_at": 1625823996,
    "left_at": 1625824035
  }
}
```

### Events from breakout rooms
For breakout room events, `is_breakout` will be `true` and `breakout_room_id` will hold the identifier of the
breakout room. The `room_name` and `roome_id` will still reference the main room.

When occupants join a breakout room, they leave the main room and enter the breakout room. You would therefore
expect to see a `muc-occupant-left` event for the main room and a `muc-occupant-joined` event for the
breakout room (as well as a `muc-room-created` event if the occupant is the first to join that breakout room).

When occupants leave a breakout room and rejoins the main room, you would see a `muc-occupant-left` event for the
breakout room and a `muc-occupant-joined` event for the main room (as well as a `muc-room-destroyed` event if
the occupant is the last to leave that breakout room).

It is worth noting that breakout rooms are not actually created when moderators create the breakout room in the UI,
and you would only get a `muc-room-created` event when an occupant moves to the breakout room.

It is also worth noting that the main room is not destroyed when everyone leaves to join a breakout room. It will only
be destroyed when the main room and all associated breakout rooms are empty.

## Installation

- Copy this script to the Prosody plugins folder. It's the following folder on
  Debian

  ```bash
  cd /usr/share/jitsi-meet/prosody-plugins/
  wget -O mod_event_sync_component.lua https://raw.githubusercontent.com/jitsi-contrib/prosody-plugins/main/event_sync/mod_event_sync_component.lua
  ```
  
- Add the component to your prosody config.

  _/etc/prosody/conf.d/meet.mydomain.com.cfg.lua_
  
  ```lua
  Component "esync.meet.mydomain.com" "event_sync_component"
      muc_component = "conference.meet.mydomain.com"
      api_prefix = "http://your.api.server/api"
  ```
  
- Restart prosody services

  ```bash
  systemctl restart prosody.service
  ```
  
### Optional config

Here's an example of the prosody config with optional configs values set:

```lua
Component "esync.meet.mydomain.com" "event_sync_component"
    muc_component = "conference.meet.mydomain.com"
    breakout_component = "breakout.meet.mydomain.com"

    api_prefix = "http://your.api.server/api"

    --- The following are all optional
    api_headers = {
        ["Authorization"] = "Bearer TOKEN-237958623045";
    }
    api_timeout = 10  -- timeout if API does not respond within 10s
    api_retry_count = 5  -- retry up to 5 times
    api_retry_delay = 1  -- wait 1s between retries

    -- change retry rules so we also retry if endpoint returns HTTP 408
    api_should_retry_for_code = function (code)
        return code >= 500 or code == 408
    end

    -- Optionally include total_dominant_speaker_time (milliseconds) in payload for occupant-left and room-destroyed
    include_speaker_stats = true
```
