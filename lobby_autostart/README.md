# Lobby Autostart

This plugin automatically enables the lobby for all rooms. 

> :warning: Do not use this plugin unless you have enabled some mechanism for moderators to bypass the lobby,
e.g. a plugin to set default passwords to rooms, or a plugin to
[bypass lobby based on token attributes](../token_lobby_bypass/). Otherwise, all your users will be stuck in
the lobby with nobody to admit them.



## Installation
- Prerequisites:
  - Enable the lobby feature and test that it works as expected when manually activated by a moderator.

  - Make sure you have a way for moderators to bypass the lobby. Test that it works when lobby is
    activated manually by another moderator.
  
  - Check that you have `/usr/share/jitsi-meet/prosody-plugins/mod_persistent_lobby.lua`. If it's not there, that means
    your version of Jitsi does not yet include [this PR](https://github.com/jitsi/jitsi-meet/pull/12215) which is required.
    - If upgrading Jitsi is not an option for you, you can still use the
      [older version of mod_lobby_autostart](../lobby_autostart/README_legacy.md)
      which does not require mod_persistent_lobby.
  

- Copy this script to the Prosody plugins folder. It's the following folder on
  Debian 

   ```bash
   cd /usr/share/jitsi-meet/prosody-plugins/
   wget -O mod_lobby_autostart.lua https://raw.githubusercontent.com/jitsi-contrib/prosody-plugins/main/lobby_autostart/mod_lobby_autostart.lua
   ```
  
- Enable the module in your prosody config, as well as the 'persistent_lobby' module.

  _/etc/prosody/conf.d/meet.mydomain.com.cfg.lua_

  ```lua
  Virtualhost "meet.mydomain.com"
    modules_enabled = {
      -- ...
      "muc_lobby_rooms";
      "persistent_lobby";
    }
  
  Component "conference.meet.mydomain.com" "muc"
    modules_enabled = {
      -- ... existing modules
      "lobby_autostart";
    }
  ```

- Restart prosody

  ```bash
  systemctl restart prosody.service
  ```
