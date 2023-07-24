# RSA Support

This module supports the following asymmetric algorithms:

- `RS256`
- `RS384`
- `RS512`

## Generating private/public key pair

```bash
openssl genrsa -out myauth 4096
openssl rsa -in myauth -pubout -outform PEM -out myauth.pub
```

`myauth` is the private key file and `myauth.pub` is the public key file. The
public key is used by the token consumer such as an API server.

The private key is used by `prosody` while signing the token.

## Module configuration for RSA

```lua
access_token_alg = "RS256"
access_token_key_file = "/path/to/myauth"
```
