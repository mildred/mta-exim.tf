variable "fqdn" {
  description = "Fully qualified domain name"
  type        = string
}

variable "relay_domains" {
  description = "List of domains to relay as a secondary MX"
  type        = list(string)
  default     = []
}

variable "local_domains" {
  description = "hash map of domains to deliver locally with their delivery methods (must include the fqdn)"
  type        = map(string)
  default     = {}
}

variable "sd_prefix" {
  description = "Systemd unit prefix"
  type        = string
  default     = ""
}

locals {
  unit_name = "${var.sd_prefix}mta-exim"
  unit_name_un = replace(local.unit_name, "-", "_")
}

module "local_domains" {
  // Terraform 0.13.x power inside !!!
  for_each = var.local_domains
  source   = "./delivery.tf"
  domain   = each.key
  method   = each.value
}

resource "sys_file" "exim_routers_conf" {
  filename = "/etc/mta-exim-routers.conf"
  content  = join("\n", [for k, v in var.local_domains: module.local_domains[k].router])
}

resource "sys_file" "exim_transports_conf" {
  filename = "/etc/mta-exim-transports.conf"
  content  = join("\n", [for k, v in var.local_domains: module.local_domains[k].transport])
}

resource "sys_package" "exim" {
  type = "deb"
  name = "exim4"
}

resource "sys_file" "exim_conf" {
  filename = "/etc/${local.unit_name}.conf"
  content  = <<CONFIG

primary_hostname = ${var.fqdn}
exim_user        = UID
exim_group       = GID
spool_directory  = /var/spool/${local.unit_name}
tls_certificate  = /etc/letsencrypt/live/${var.fqdn}/fullchain.pem
tls_privatekey   = /etc/letsencrypt/live/${var.fqdn}/privkey.pem

.ifdef BIND_PORTS
daemon_smtp_ports = <, BIND_PORTS
.else
daemon_smtp_ports = <, 25
.endif

.ifdef BIND_ADDRS
local_interfaces  = <, BIND_ADDRS
.endif

domainlist local_domains    = ${var.fqdn} : localhost : localhost.localdomain
domainlist relay_to_domains =
hostlist   relay_from_hosts = localhost

${file("${path.module}/mta-exim.conf")}

CONFIG
}

resource "sys_file" "exim_socket" {
  filename = "/etc/systemd/system/${local.unit_name}.socket"
  content = <<CONF
[Unit]
Description=EXIM SMTP server
After=network.target
Conflicts=exim4.service

[Socket]
ListenStream=[::]:25
BindIPv6Only=both

[Install]
WantedBy=multi-user.target

CONF
}

resource "sys_file" "exim_service" {
  filename = "/etc/systemd/system/${local.unit_name}.service"
  content = <<CONF
[Unit]
Description=EXIM SMTP server
After=network.target
Conflicts=exim4.service
Requires=addr@${local.unit_name}.service
After=addr@${local.unit_name}.service

[Service]
EnvironmentFile=/run/addr/${local.unit_name}.env
User=Debian-exim
Group=Debian-exim
ExecStartPre=+/usr/bin/mkdir -p /var/spool/${local.unit_name}
ExecStartPre=+/usr/bin/chown Debian-exim:Debian-exim /var/spool/${local.unit_name}
ExecStart=/bin/sh -c ' \
  exec /usr/local/bin/force-bind \
  -m :25=sd-0 \
  exec /usr/sbin/exim4 \
    -C ${sys_file.exim_conf.filename} \
    -DCONF_ROUTERS=${sys_file.exim_routers_conf.filename} \
    -DCONF_TRANSPORTS=${sys_file.exim_transports_conf.filename} \
    -DUID=$(id -u Debian-exim) -DGID=$(id -g Debian-exim) \
    -bdf -q1h \
'

CONF
}

resource "sys_systemd_unit" "exim4" {
  name = "exim4.service"
  start = false
  enable = false
}

resource "sys_systemd_unit" "exim" {
  name = "${local.unit_name}.socket"
  enable = true
  start  = true
  restart_on = {
    service_unit = sys_file.exim_service.id
    socket_unit  = sys_file.exim_socket.id
  }
  depends_on = [ sys_systemd_unit.exim4 ]
}

/*

module "exim_proxy_service" {
  source    = "../sd-proxy.tf"
  unit_name = local.unit_name
  bind4     = "0.0.0.0"
  bind6     = "[::]"
  host4     = "$${HOST_${local.unit_name_un}4}"
  host6     = "[$${HOST_${local.unit_name_un}6}]"
  ports = {
    smtp4 = [25, 1025]
    smtp6 = [25, 1025]
  }
}

resource "sys_file" "exim_proxy_service" {
  filename = "/etc/systemd/system/${local.unit_name}-proxy.service"
  content = <<EOF
[Unit]
Description=Exim socket-activated proxy
Requires=addr@${local.unit_name}.service
After=addr@${local.unit_name}.service

[Service]
EnvironmentFile=/run/addr/${local.unit_name}.env
${module.exim_proxy_service.service}


[Install]
WantedBy=multi-user.target
EOF
}

resource "sys_systemd_unit" "exim_proxy" {
  name = "${local.unit_name}-proxy.service"
  start = true
  enable = true
  restart_on = {
    unit = sys_file.exim_proxy_service.id
  }
  depends_on = [ sys_systemd_unit.exim ]
}

*/
