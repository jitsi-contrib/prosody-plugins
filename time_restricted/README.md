# Time Restricted

This plugin sets a time limit to the conference.

## Installation

- Copy this script to the Prosody plugins folder. It's the following folder on
  Debian

  ```bash
  cd /usr/share/jitsi-meet/prosody-plugins/
  wget -O mod_time_restricted.lua https://raw.githubusercontent.com/jitsi-contrib/prosody-plugins/main/time_restricted/mod_time_restricted.lua
  ```

- Enable module in your prosody config.

  _/etc/prosody/conf.d/meet.mydomain.com.cfg.lua_

  ```lua
  Component "conference.meet.mydomain.com" "muc"
    modules_enabled = {
      ...
      ...
      "time_restricted";
    }
    conference_max_minutes = 10
  ```

- Restart the services

  ```bash
  systemctl restart prosody.service
  systemctl restart jicofo.service
  ```
