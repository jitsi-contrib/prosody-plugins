# proxybased_external_services
This module is dervied from jitsi's original `external_services` module and allows you to set the host of the services via an http header. \
This is useful when you want to redirect different clients to different services. \
The module currently supports WebSocket and Bosh connections.

The module should **not** be enabled together with `external_services`. If both modules are enabled at the same time, unexpected behaviour may occur.

## Installation
- Copy this script to the Prosody plugins folder. It's the following folder on
  Debian:

  ```bash
  cd /usr/share/jitsi-meet/prosody-plugins/
  wget -O mod_proxybased_external_services.lua https://raw.githubusercontent.com/jitsi-contrib/prosody-plugins/main/proxybased_external_services/mod_proxybased_external_services.lua
  ```

- Enable module in your prosody config.

  _/etc/prosody/conf.d/meet.mydomain.com.cfg.lua_

  ```lua
  Component "conference.meet.mydomain.com" "muc"
    modules_enabled = {
      ...
      ...
      -- "external_services";
      "proxybased_external_services";
    }
  ```

- Restart Prosody

  ```bash
  systemctl restart prosody.service
  ```

## Configuration
The configuration is like the original `external_services` module. All that has been added is the new `proxybased_external_service_host_header` attribute, which defines a header from which the host for the services is taken. If the header cannot be found in a request, the host from the service configuration will be used as a default. \
The default header used is `Turn-Server`.
```lua
proxybased_external_service_secret = "<SECRET>";
proxybased_external_service_host_header = "Turn-Server"
-- 'some-turn-server' is the default host used when the `Turn-Server` header could not be found in a request
proxybased_external_services = {
     { type = "turns", host = "some-turn-server", port = 443, transport = "tcp", secret = true, ttl = 86400, algorithm = "turn" }
};
```

## Example HAProxy configuration
The following example shows how an HA proxy sitting in front of Prosody can be configured if internal and external clients are to be rooted to different turn servers.

```haproxy
# Turn Settings for external clients
http-request set-header Turn-Server external-turn1.example.de if { hdr_ip(x-forwarded-for) 0.0.0.0/0 }
# Turn Settings for internal clients
http-request set-header Turn-Server internal-turn1.example.de if { hdr_ip(x-forwarded-for) 10.0.0.0/8 }
```
