# Lobby Autostart

This plugin automatically enables the lobby for all rooms. 

:warning: Do not use this plugin unless you have enabled some mechanism for moderators to bypass the lobby. 
Otherwise, all your users will be stuck in 
the lobby with nobody to admit them.



## Installation
- Prerequisites:
  - Enable the lobby feature and test that it works as expected when manually
activated by a moderator. 

  - Make sure you have a way for moderators to bypass the lobby e.g. a plugin to set default passwords to rooms, or a plugin 
to bypass tokens based on JWT token attributes. Test that it works when lobby is activated manually by another moderator.

  
- Copy this script to the Prosody plugins folder. It's the following folder on
  Debian 

   ```bash
   cd /usr/share/jitsi-meet/prosody-plugins/
   wget -O mod_lobby_autostart.lua https://raw.githubusercontent.com/jitsi-contrib/prosody-plugins/main/lobby_autostart/mod_lobby_autostart.lua
   ```
  
- Enable module in your prosody config.

  _/etc/prosody/conf.d/meet.mydomain.com.cfg.lua_

  ```lua
  VirtualHost "meet.mydomain.com"
    modules_enabled = {
      -- ... existing modules
      "lobby_autostart";
    }
  ```

- Restart prosody

  ```bash
  systemctl restart prosody.service
  ```
