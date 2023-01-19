# Access Token

This plugin provides a token that proves its owner is a participant in the
`Jitsi` meeting room.

Let's say you have an API service and you want to allow the user to send
requests if they are an active user of a meeting. In this case, you may use this
module.

## Installation

- Copy this script to the Prosody plugins folder. It's the following folder on
  Debian:

  ```bash
  cd /usr/share/jitsi-meet/prosody-plugins/
  wget -O mod_access_token.lua https://raw.githubusercontent.com/jitsi-contrib/prosody-plugins/main/access_token/mod_access_token.lua
  ```

- Enable module in your prosody config.

  _/etc/prosody/conf.d/meet.mydomain.com.cfg.lua_

  ```lua
  Component "conference.meet.mydomain.com" "muc"
    modules_enabled = {
      "access_token";
  ```

- Restart the services

  ```bash
  systemctl restart prosody.service
  ```
