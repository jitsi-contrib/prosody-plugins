# Prosody plugins

- [event sync](event_sync/)

  Sends HTTP POST to external API when occupant or room events triggered.

- [frozen nick](frozen_nick/)

  Prevents users from changing display name set by JWT auth.

- [jibri autostart](jibri_autostart/)

  Automatically start recording when the moderator comes into the room.

- [lobby autostart](lobby_autostart/)

  Automatically enables the lobby for all rooms. 

- [time restricted](time_restricted/)

  Sets a time limit to the conference.

- [token affiliation](token_affiliation/)

  Sets the occupant's affiliation according to the token content.

- [token_lobby_bypass](token_lobby_bypass/)

  Enables some users to bypass lobby based on token content.

- [token_lobby_ondemand](token_lobby_ondemand/)

  Selectively send users to lobby based on token content. Enables lobby automatically if not yet activated.

- [token owner party](token_owner_party/)

  Prevents the unauthorized users to create a room and terminates the conference
  when the owner leaves.
