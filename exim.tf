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
  filename = "/etc/mta-exim.conf"
  content  = file("${path.module}/mta-exim.conf")
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
#CapabilityBoundingSet=CAP_NET_BIND_SERVICE
#AmbientCapabilities=CAP_NET_BIND_SERVICE
ExecStart=/bin/sh -c ' \
  exec /usr/sbin/exim4 \
  -C ${sys_file.exim_conf.filename} \
  -DCONF_ROUTERS=${sys_file.exim_routers_conf.filename} \
  -DCONF_TRANSPORTS=${sys_file.exim_transports_conf.filename} \
  -DSMTP_PORT=1025 \
  -DBIND_ADDRS=$${HOST_${local.unit_name}4},$${HOST_${local.unit_name}6} \
  -DFQDN=${var.fqdn} \
  -DSPOOL=/var/spool/exim4 \
  -DTLS_CERT=/etc/letsencrypt/live/${var.fqdn}/fullchain.pem \
  -DTLS_SKEY=/etc/letsencrypt/live/${var.fqdn}/privkey.pem \
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
  name = "${local.unit_name}.service"
  enable = false
  restart_on = {
    unit = sys_file.exim_service.id
  }
  depends_on = [ sys_systemd_unit.exim4 ]
}

module "exim_proxy_service" {
  source    = "../sd-proxy.tf"
  unit_name = local.unit_name
  bind4     = "0.0.0.0"
  bind6     = "[::]"
  host4     = "$${HOST_${local.unit_name}4}"
  host6     = "[$${HOST_${local.unit_name}6}]"
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

