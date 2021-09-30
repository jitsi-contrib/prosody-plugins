# Jibri Autostart

This plugin automatically starts recording when the moderator comes into the room.

## Installation

- Copy this script to the Prosody plugins folder. It's the following folder on
  Debian

  ```bash
  cd /usr/share/jitsi-meet/prosody-plugins/
  wget -O mod_jibri_autostart.lua https://raw.githubusercontent.com/jitsi-contrib/prosody-plugins/main/jibri_autostart/mod_jibri_autostart.lua
  ```

- Enable module in your prosody config.

  _/etc/prosody/conf.d/meet.mydomain.com.cfg.lua_

  ```lua
  Component "conference.meet.mydomain.com" "muc"
    modules_enabled = {
      ...
      ...
      "jibri_autostart";
    }
  ```

- Restart the services

  ```bash
  systemctl restart prosody.service
  systemctl restart jicofo.service
  ```
