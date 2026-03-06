# Per Room Time Restricted

This plugin allows you to set a time limit to the conference based on the room name or subdomain.

## Installation

- Copy this script to the Prosody plugins folder. It's the following folder on
  Debian

  ```bash
  cd /usr/share/jitsi-meet/prosody-plugins/
  wget -O mod_per_room_time_restricted.lua https://raw.githubusercontent.com/jitsi-contrib/prosody-plugins/main/per_room_time_restricted/mod_per_room_time_restricted.lua
  ```

- Enable the module in your prosody config.

  _/etc/prosody/conf.d/meet.mydomain.com.cfg.lua_

  ```lua
  Component "conference.meet.mydomain.com" "muc"
    modules_enabled = {
      -- ... existing modules
      "per_room_time_restricted";
    }

    conference_max_minutes = 10 -- default time limit for all rooms

    --- configure you overrides --

    max_minutes_for_rooms = {   -- define this to set limit for specific rooms
      detention = 30;  -- set time limit for "/detention" to 30 minutes
      ["[classroom]cs101"] = 100;  -- set time limit for "/classroom/cs101" to 100 minutes
    }

    max_minutes_for_subdomains = {   -- define this to set limits based on subdomain
      classroom = 40;  -- set time limit for "/classroom/*" rooms to 40 minutes
      assembly = 200;  -- set time limit for "/assembly/*" rooms to 200 minutes
    }
  ```

  If a room matches entries in both `max_minutes_for_rooms` and
  `max_minutes_for_subdomains` -- e.g. in the case of `/classroom/cs101` in
  the example config above -- then `max_minutes_for_rooms` takes precedence.

- Restart the services

  ```bash
  systemctl restart prosody.service
  systemctl restart jicofo.service
  ```
