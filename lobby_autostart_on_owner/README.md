# Lobby Autostart (on owner)

This plugin automatically manages lobby activation and moderator assignment:

- **When a new owner (moderator) joins**, it automatically enables the lobby for the room if not already active.
- **When the last owner leaves**, it automatically promotes one of the remaining participants (`member`) to `owner` to ensure someone can admit users from the lobby.

## Known Issues

- When authorization is required to create a room (e.g., JWT authentication is enabled), participants who were waiting before the moderator joined may enter the room directly without passing through the lobby.
  This happens because the lobby is activated shortly *after* the moderator joins.

## Installation
- **Installing the plugin:**

  ```bash
  cd /usr/share/jitsi-meet/prosody-plugins/
  wget -O mod_lobby_autostart_on_owner.lua https://raw.githubusercontent.com/jitsi-contrib/prosody-plugins/main/lobby_autostart_on_owner/mod_lobby_autostart_on_owner.lua
  ```

- **Configuring Prosody:**

  Edit your `/etc/prosody/conf.d/meet.mydomain.com.cfg.lua`:

  ```lua
  Component "conference.meet.mydomain.com" "muc"
    modules_enabled = {
      -- ... existing modules
      "lobby_autostart_on_owner";
    }
  ```

- **Restart Prosody:**

  ```bash
  systemctl restart prosody.service
  ```

## Installation in Docker
- **Installing the plugin:**
  ```bash
  cd ${CONFIG}/prosody/prosody-plugins/custom
  wget -O mod_lobby_autostart_on_owner.lua https://raw.githubusercontent.com/jitsi-contrib/prosody-plugins/main/lobby_autostart_on_owner/mod_lobby_autostart_on_owner.lua
  ```

- **Edit your `.env` file:**

  ```
  XMPP_MUC_MODULES=...,lobby_autostart_on_owner
  ```

- **Restart the containers:**

  ```bash
  docker-compose down
  docker-compose up -d
  ```