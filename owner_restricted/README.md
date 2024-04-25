# Owner Restricted

This plugin allows the conference if there is a moderator (`owner`) in the room.

It doesn't prevent guests to join the room but ends the meeting if there is
still no moderator after `timeout`.

When the last moderator leaves the room, it waits `timeout` seconds and ends the
meetinf if the moderator doesn't come back.

## Installation

- Copy this script to the Prosody plugins folder. It's the following folder on
  Debian

  ```bash
  cd /usr/share/jitsi-meet/prosody-plugins/
  wget -O mod_owner_restricted.lua https://raw.githubusercontent.com/jitsi-contrib/prosody-plugins/main/owner_restricted/mod_owner_restricted.lua
  ```

- Enable module in your prosody config.

  _/etc/prosody/conf.d/meet.mydomain.com.cfg.lua_

  ```lua
  Component "conference.meet.mydomain.com" "muc"
    modules_enabled = {
      ...
      ...
      "owner_restricted";
    }

    role_timeout = 60;
  ```

- Restart the services

  ```bash
  systemctl restart prosody.service
  systemctl restart jicofo.service
  ```

## Sponsors

[![Nordeck](/images/nordeck.png)](https://nordeck.net/)
