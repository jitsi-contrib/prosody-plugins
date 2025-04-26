# Per Room Max Occupants

This plugin extends the capabilities of mod_muc_max_occupants by allowing you to
set different max occupancy values based on the room name or subdomain.

## Installation

- Copy this script to the Prosody plugins folder. It's the following folder on
  Debian

  ```bash
  cd /usr/share/jitsi-meet/prosody-plugins/
  wget -O mod_per_room_max_occupants.lua https://raw.githubusercontent.com/jitsi-contrib/prosody-plugins/main/per_room_max_occupants/mod_per_room_max_occupants.lua
  ```

- Enable the module in your prosody config, as well as the 'muc_max_occupants'
  module.

  _/etc/prosody/conf.d/meet.mydomain.com.cfg.lua_

  ```lua
  Component "conference.meet.mydomain.com" "muc"
    modules_enabled = {
      -- ... existing modules
      "muc_max_occupants";  -- comes with Jitsi Meet
      "per_room_max_occupants";  -- plugin we're installing now 
    }

    muc_max_occupants = 5  -- default max occupants for all rooms
    muc_access_whitelist = { "focus@auth.meet.example.com" }  -- jicofo should be excluded from occupancy count

    --- configure you overrides --

    max_occupants_for_rooms = {   -- define this to set limit for specific rooms
      detention = 30;  -- increase limit for "/detention" to 30
      ["[classroom]cs101"] = 100;  -- increase limit for "/classroom/cs101" to 100
    }

    max_occupants_for_subdomains = {   -- define this to set limits based on subdomain
      classroom = 40;  -- increase limit for "/classroom/*" rooms to 40  
      assembly = 200;  -- increase limit for "/assembly/*" rooms to 200  
    }
  ```

  If a room matches entries in both `max_occupants_for_rooms` and
  `max_occupants_for_subdomains` -- e.g. in the case of `/classroom/cs101` in
  the example config above -- then `max_occupants_for_rooms` takes precedence.

- Restart prosody

  ```bash
  systemctl restart prosody.service
  ```
