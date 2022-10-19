# Secure Domain Lobby Bypass

This plugin allows you to let some users bypass the lobby based on the
authentication.

> This module works only for BOSH clients. It doesn't support `XMPP websocket`.

## Installation

- Set up
  [secure domain](https://jitsi.github.io/handbook/docs/devops-guide/secure-domain/)
  and check that it works before proceeding.

- Copy this script to the Prosody plugins folder. It's the following folder on
  Debian:

  ```bash
  cd /usr/share/jitsi-meet/prosody-plugins/
  wget -O mod_secure_domain_lobby_bypass.lua https://raw.githubusercontent.com/jitsi-contrib/prosody-plugins/main/secure_domain_lobby_bypass/mod_secure_domain_lobby_bypass.lua
  ```

- Enable module in your prosody config.

  _/etc/prosody/conf.d/meet.mydomain.com.cfg.lua_

  ```lua
  Component "conference.meet.mydomain.com" "muc"
    modules_enabled = {
      -- ... existing modules
      "secure_domain_lobby_bypass";
    }
  ```

- Restart the services

  ```bash
  systemctl restart prosody.service
  ```
