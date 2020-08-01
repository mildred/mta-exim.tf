Exim Mail Transfer Agent
========================

This module will set up on the host running it a mail transfer agent (MTA) using
the Exim software.  It will only function as a MTA and in  particular  will  not
handle mail submission (authenticated or local), DKIM signing,  local  delivery.
This is enforced to ensure the most strict security and to run the MTA with  the
least priviledges.

Features include:

- Running only on port 25
- STARTTLS with externally provided certificates
- Only accepting e-mails for one of the local or relayed domains
- accept deliveries using SMTP or LMTP

Requirements
------------

- [`terraform-provider-sys`](https://github.com/mildred/terraform-provider-sys)
  needs to be manually installed until i split this provider into better suited
  providers.
- [force-bind](https://github.com/mildred/force-bind-seccomp) needs to be
  installed separately in `/usr/local/bin/force-bind`

Configuration
-------------

### `fqdn`

The fully qualified domain name to advertise on HELO. Will be a local delivery
domain.

### `local_domains`

Hash map containins as keys the local domains to be delivered locally as as
value the delivery method. Valid delivery methods are:

- `lmtp:/path/to/unix.sock`: the path must contain at least one `/` to be
  detected as a unix socket.

- `lmtp:hostname:port`: deliver using LMTP over TCP with hiven hostname and port

### `relay_domains`

List of domains to relay

### `sd_prefix`

Systemd prefix to include before the systemd unit names.

