variable "fqdn" {
  description = "Fully qualified domain name"
  type        = string
}

variable "sockets" {
  description = "List of socket files to provide ACL access to Exim"
  default     = []
}

variable "relay_domains" {
  description = "List of domains to relay as a secondary MX (not implemented)"
  type        = list(string)
  default     = []
}

variable "local_domains" {
  description = "hash map of domains to deliver locally with their delivery methods (must include the fqdn)"
  type        = map(string)
  default     = {}
}

variable "virtual_domains" {
  description = "enable the virtual domain support"
  type        = bool
  default     = false
}

variable "virtual_domains_transport" {
  description = "Transport for the virtual domains"
  type        = string
  default     = ""
}

variable "virtual_domains_sockapi" {
  description = "Socket address for virtual domain lookup"
  type        = string
  default     = ""
}

variable "sd_prefix" {
  description = "Systemd unit prefix"
  type        = string
  default     = ""
}

variable "cert_source" {
  description = "Where to find certificates (certbot, caddy)"
  type        = string
  default     = "certbot"
}

variable "caddy_cert_dir" {
  description = "When using cert_source=caddy, where are the certificates"
  type        = string
  default     = "/var/lib/caddy/certificates"
  // Could be also at var/lib/caddy/.local/share/caddy/certificates
}

variable "caddy_cert_provider" {
  description = "When using cert_source=caddy, the certificate subdirectory"
  type        = string
  default     = "acme-v02.api.letsencrypt.org-directory"
}

variable "listen_port" {
  type = number
  default = 25
}

variable "debug" {
  type = bool
  default = false
}

variable "debug_categories" {
  type = list
  default = ["+all"]
}

locals {
  sockets = concat(
    var.sockets,
    compact([for k, v in var.local_domains: module.local_domains[k].socket]),
    compact(module.virtual_domains.*.socket))

  unit_name = "${var.sd_prefix}mta-exim"
  unit_name_un = replace(local.unit_name, "-", "_")

  tls_certificate = lookup({
    certbot = "/etc/letsencrypt/live/${var.fqdn}/fullchain.pem"
    caddy   = "${var.caddy_cert_dir}/${var.caddy_cert_provider}/${var.fqdn}/${var.fqdn}.crt"
  }, var.cert_source, "/etc/ssl/certs/${var.fqdn}.pem")

  tls_privatekey  = lookup({
    certbot = "/etc/letsencrypt/live/${var.fqdn}/privkey.pem"
    caddy   = "${var.caddy_cert_dir}/${var.caddy_cert_provider}/${var.fqdn}/${var.fqdn}.key"
  }, var.cert_source, "/etc/ssl/private/${var.fqdn}.pem")
}

module "local_domains" {
  // Terraform 0.13.x power inside !!!
  for_each = var.local_domains
  source   = "./delivery.tf"
  domain   = each.key
  method   = each.value
  prefix   = "local_"
}

module "virtual_domains" {
  count   = var.virtual_domains ? 1 : 0
  source  = "./delivery.tf"
  domain  = "domains"
  method  = var.virtual_domains_transport
  prefix  = "virtual_"
  sockapi = var.virtual_domains_sockapi
}

locals {
  #virtual_exec_start_pre = var.virtual_domains ? "ExecStartPre=-/usr/local/bin/http-config-fs --file domains.json ${var.virtual_domains_lookup} /run/${local.unit_name}/virtual-domains" : ""
  #virtual_exec_stop_post = var.virtual_domains ? "ExecStopPost=-/usr/bin/fusermount -u /run/${local.unit_name}/virtual-domains/" : ""
  virtual_exec_start_pre = ""
  virtual_exec_stop_post = ""
}

resource "sys_file" "http-config-fs" {
  filename        = "/usr/local/bin/http-config-fs"
  source          = "https://github.com/mildred/http-config-fs/releases/download/latest-master/http-config-fs"
  file_permission = 0755
}

locals {
  virtual_json_file = "/run/${local.unit_name}/virtual-domains/domains.json"
  virtual_domains_aliases = <<EXIM

virtual_aliases:
  driver = redirect
  #data = $${lookup {domains : $domain : mailboxes : $local_part} json {${local.virtual_json_file}} \
  #  {} \
  #  {$${lookup {domains : $domain : aliases : $local_part : alias} json {${local.virtual_json_file}} \
  #    {$value} \
  #    {$${lookup {domains : $domain : catchall} json {${local.virtual_json_file}}}} \
  #  }} \
  #}
  data = $${readsocket{${var.virtual_domains_sockapi}}{req=getalias&failure=&domain64=$${base64:$domain}&localpart64=$${base64:$local_part}}}

EXIM

  exim_conf = <<EXIM

primary_hostname = ${var.fqdn}
exim_user        = UID
exim_group       = GID
spool_directory  = /var/spool/${local.unit_name}
log_file_path    = /var/log/${local.unit_name}/%slog
tls_certificate  = ${local.tls_certificate}
tls_privatekey   = ${local.tls_privatekey}

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

${local.exim_conf_file}

EXIM

  exim_conf_file = templatefile("${path.module}/mta-exim.conf", {
    "relay_acl_condition" = (var.virtual_domains ?
      "$${readsocket{${var.virtual_domains_sockapi}}{req=checkdomain&domain64=$${base64:$domain}&true=true&false=false}}" :
      "false")
  })
}

resource "sys_file" "exim_routers_conf" {
  filename = "/etc/mta-exim-routers.conf"
  content  = join("\n", concat(
    [for k, v in var.local_domains: module.local_domains[k].router],
    var.virtual_domains ? [local.virtual_domains_aliases, module.virtual_domains[0].virtual_router] : []))
}

resource "sys_file" "exim_transports_conf" {
  filename = "/etc/mta-exim-transports.conf"
  content  = join("\n", concat(
    [for k, v in var.local_domains: module.local_domains[k].transport],
    var.virtual_domains ? [module.virtual_domains[0].transport] : []))
}

resource "sys_package" "exim" {
  type = "deb"
  name = "exim4"
}

resource "sys_file" "exim_conf" {
  filename = "/etc/${local.unit_name}.conf"
  content  = local.exim_conf
}

resource "sys_file" "exim_socket" {
  filename = "/etc/systemd/system/${local.unit_name}.socket"
  content = <<CONF
[Unit]
Description=EXIM SMTP server
After=network.target
Conflicts=exim4.service
GenerateAddr=${local.unit_name}
Requires=addr@${local.unit_name}.service

[Socket]
ListenStream=[$${addr6@${local.unit_name}}]:${var.listen_port}
ListenStream=$${addr4@${local.unit_name}}:${var.listen_port}
#BindIPv6Only=both

[Install]
WantedBy=multi-user.target
GeneratedAddrWantedBy=multi-user.target

CONF
}

resource "sys_file" "exim_service" {
  filename = "/etc/systemd/system/${local.unit_name}.service"
  content = <<CONF
[Unit]
Description=EXIM SMTP server
After=network.target
Conflicts=exim4.service
Requires=addr@${local.unit_name}.service ${local.unit_name}.socket
After=addr@${local.unit_name}.service ${local.unit_name}.socket

[Service]
EnvironmentFile=/run/addr/${local.unit_name}.env
User=Debian-exim
Group=Debian-exim

ExecStartPre=+/usr/bin/mkdir -p \
  /var/spool/${local.unit_name} \
  /var/log/${local.unit_name} \
  /run/${local.unit_name}/virtual-domains/
ExecStartPre=+/usr/bin/chown Debian-exim:Debian-exim \
  /var/spool/${local.unit_name} \
  /var/log/${local.unit_name} \
  /run/${local.unit_name}/virtual-domains/

${ length(local.sockets) > 0 ? "ExecStartPre=+/usr/bin/setfacl -m u:Debian-exim:rwX,g:Debian-exim:rwX ${join(" ", local.sockets)}" : "" }
${local.virtual_exec_start_pre}

ExecStartPre=/bin/echo "Logs are in /var/log/${local.unit_name}/"
ExecStart=/bin/sh -c ' \
  exec /usr/local/bin/force-bind -v \
  -m [::]:25/0=sd-0 \
  -m 0.0.0.0:25/0=sd-1 \
  /usr/sbin/exim4 \
    ${var.debug ? "-d${join(",", var.debug_categories)}" : ""} \
    -C ${sys_file.exim_conf.filename} \
    -DCONF_ROUTERS=${sys_file.exim_routers_conf.filename} \
    -DCONF_TRANSPORTS=${sys_file.exim_transports_conf.filename} \
    -DUID=$(id -u Debian-exim) -DGID=$(id -g Debian-exim) \
    -bdf -q1h \
'

${local.virtual_exec_stop_post}

CONF
}

resource "sys_systemd_unit" "exim4" {
  name = "exim4.service"
  start = false
  mask = true
}

resource "sys_systemd_unit" "exim" {
  name = "${local.unit_name}.socket"
  enable = true
  start  = true
  restart_on = {
    service_unit = sys_file.exim_service.id
    socket_unit  = sys_file.exim_socket.id
    conf         = sys_file.exim_conf.id
    routers_conf    = sys_file.exim_routers_conf.id
    transports_conf = sys_file.exim_transports_conf.id
  }
  depends_on = [ sys_systemd_unit.exim4 ]
}


output "sd_addr" {
  value = local.unit_name
}
