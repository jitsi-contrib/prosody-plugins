# Prosody plugins

- [access_token](access_token/)

  Provides a token that proves its owner is a participant of an ongoing `Jitsi`
  meeting.

- [auth_hybrid_matrix_token](auth_hybrid_matrix_token/)

  Provides an authentication provider for `Prosody` which supports `Matrix` and
  standard `Jitsi` token at the same time.

- [event sync](event_sync/)

  Sends HTTP POST to external API when occupant or room events triggered.

- [frozen nick](frozen_nick/)

  Prevents users from changing display name set by JWT auth.

- [jibri autostart](jibri_autostart/)

  Automatically start recording when the moderator comes into the room.

- [lobby autostart](lobby_autostart/)

  Automatically enables the lobby for all rooms.

- [lobby deactivate](lobby_deactivate/)

  Deactivate the lobby after the first authorized participant joins.

- [owner restricted](owner_restricted/)

  Allows the conference if there is a moderator (`owner`) in the room.

- [per room max occupants](per_room_max_occupants/)

  Extends the capabilities of mod_muc_max_occupants by allowing different max
  occupancy based on the room name or subdomain.

- [secure domain lobby bypass](secure_domain_lobby_bypass/)

  Enables some users to bypass lobby based on the authentiation.

- [time restricted](time_restricted/)

  Sets a time limit to the conference.

- [token affiliation](token_affiliation/)

  Sets the occupant's affiliation according to the token content.

- [token no wildcard](token_no_wildcard/)

  Enforces single room per token by rejecting tokens that use wildcards or
  regex-based room names.

- [token lobby bypass](token_lobby_bypass/)

  Enables some users to bypass lobby based on token content.

- [token lobby ondemand](token_lobby_ondemand/)

  Selectively send users to lobby based on token content. Enables lobby
  automatically if not yet activated.

- [token owner party](token_owner_party/)

  Prevents the unauthorized users to create a room and terminates the conference
  when the owner leaves.

- [token security_ondemand](token_security_ondemand/)

  Selectively enable/disable lobby or set/unset password for a meeting room
  based on token content.
