# Frozen Nick

This plugin stops users from changing display name if JWT auth is used and name is provided in token context.

This is useful in a setup where user identity is established in another app and passed to Jitsi via JWT. Allowing users
to change display name from a client app weakens the link between Jitsi user and in-app user identity. 


## Installation

- Copy this script to the Prosody plugins folder. It's the following folder on
  Debian:

  ```bash
  cd /usr/share/jitsi-meet/prosody-plugins/
  wget -O mod_frozen_nick.lua https://raw.githubusercontent.com/jitsi-contrib/prosody-plugins/main/frozen_nick/mod_frozen_nick.lua
  ```

- Enable module in your prosody config.

  _/etc/prosody/conf.d/meet.mydomain.com.cfg.lua_
  
  ```lua
  VirtualHost "meet.mydomain.com"
    modules_enabled = {
      -- ... existing modules
      "frozen_nick";
    }
  
  ```
  
- Restart the services

  ```bash
  systemctl restart prosody.service
  ```
  
