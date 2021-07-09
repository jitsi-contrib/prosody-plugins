# Event Sync

This prosody sends HTTP POST request with JSON payload to external API when occupant or room events are triggered.

If JWT token auth is used, name and email from the user context is also included in the JSON
payload for occupant data.


## Events

### muc-room-created

When a room is created, `POST ${api_prefix}/events/room/created` is called with JSON payload containing:
* event_name
* room_name
* room_jid
* created_at

Example:

```json
{
  "event_name": "muc-room-created",
  "room_name": "catchup",
  "room_jid": "catchup@conference.domain.com",
  "created_at": 1625823996
}
```

### muc-room-destroyed

When a room is destroyed, `POST ${api_prefix}/events/room/destroyed` is called with JSON payload containing:
* event_name
* room_name
* room_jid
* created_at
* destroyed_at
* all_occupants (list of all occupants that has joined since room created)

Example:

```json
{
  "event_name": "muc-room-created",
  "room_name": "catchup",
  "room_jid": "catchup@conference.domain.com",
  "created_at": 1625823996,
  "destroyed_at": 1625824035,
  "all_occupants": [
    {
      "name": "James Barrow",
      "email": "j.barrow@domain.com",
      "id": "00380324-a840-400d-880f-7ee0933b7556",
      "occupant_jid": "14f01c40-5195-4a4d-8efb-f58b49d18741@domain.com/OWhl8jSh"
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
* occupant
    * occupant_jid
    * joined_at
    * name (if JWT token auth used. Take from user context.)
    * email (if JWT token auth used. Take from user context.)
    * id (if JWT token auth used. Take from user context.)

Example:

```json
{
  "event_name": "muc-occupant-joined",
  "room_name": "catchup",
  "room_jid": "catchup@conference.domain.com",
  "occupant": {
    "name": "James Barrow",
    "email": "j.barrow@domain.com",
    "id": "00380324-a840-400d-880f-7ee0933b7556",
    "occupant_jid": "14f01c40-5195-4a4d-8efb-f58b49d18741@domain.com/OWhl8jSh"
    "joined_at": 1625823996
  }
}
```

### muc-occupant-left

When an occupant leaves, `POST ${api_prefix}/events/occupant/left` is called with JSON payload containing:
* event_name
* room_name
* room_jid
* occupant
    * occupant_jid
    * joined_at
    * left_at
    * name (if JWT token auth used. Take from user context.)
    * email (if JWT token auth used. Take from user context.)
    * id (if JWT token auth used. Take from user context.)

Example:

```json
{
  "event_name": "muc-occupant-left",
  "room_name": "catchup",
  "room_jid": "catchup@conference.domain.com",
  "occupant": {
    "name": "James Barrow",
    "email": "j.barrow@domain.com",
    "id": "00380324-a840-400d-880f-7ee0933b7556",
    "occupant_jid": "14f01c40-5195-4a4d-8efb-f58b49d18741@domain.com/OWhl8jSh"
    "joined_at": 1625823996,
    "left_at": 1625824035
  }
}
```


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
  Component "event_sync.domain.com" "event_sync_component"
      muc_component = "conference.domain.com"
      api_prefix = "http://your.api.server/api"
  ```
  
- Restart prosody services

  ```bash
  systemctl restart prosody.service
  ```
  
### Optional config

Here's an example of the prosody config with optional configs values set:

```lua
Component "event_sync.domain.com" "event_sync_component"
    muc_component = "conference.domain.com"
    api_prefix = "http://your.api.server/api"
    
    --- The following are all optional
    api_headers = {
        ["Authorization"] = "Bearer TOKEN-237958623045";
    }
    api_timeout = 10  -- timeout if API does not respond within 10s
    retry_count = 5  -- retry up to 5 times
    api_retry_delay = 1  -- wait 1s between retries
    
    -- change retry rules so we also retry if endpoint returns HTTP 408
    api_should_retry_for_code = function (code)
        return code >= 500 or code == 408
    end
```