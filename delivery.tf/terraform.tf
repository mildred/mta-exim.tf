variable "domain" {
}

variable "method" {
}

locals {
  id           = replace(var.domain, ".", "_")
  method_parts = regex("^([^:]*):(.*)$", var.method)
  delivery     = ( (length(regexall("^lmtp:[^/]*$", var.method)) > 0) ? "lmtp-tcp" :
                   (length(regexall("^lmtp:.*$", var.method)) > 0)    ? "lmtp-unix" :
                   local.method_parts[0])
  value        = local.method_parts[1]
}

data "template_file" "lmtp_tcp_router" {
  count    = local.delivery == "lmtp-tcp" ? 1 : 0
  template = file("${path.module}/mta-exim-router-${local.delivery}.conf")
  vars = {
    id     = local.id
    domain = var.domain
    host   = regex("^(.*):([0-9]+)$", local.value)[0]
    port   = regex("^(.*):([0-9]+)$", local.value)[1]
  }
}

data "template_file" "lmtp_unix_router" {
  count    = local.delivery == "lmtp-unix" ? 1 : 0
  template = file("${path.module}/mta-exim-router-${local.delivery}.conf")
  vars = {
    id     = local.id
    domain = var.domain
    socket = local.value
  }
}

output "router" {
  value = join("", concat(
        data.template_file.lmtp_tcp_router.*.rendered,
        data.template_file.lmtp_unix_router.*.rendered))
}

data "template_file" "lmtp_tcp_transport" {
  count    = local.delivery == "lmtp-tcp" ? 1 : 0
  template = file("${path.module}/mta-exim-transport-${local.delivery}.conf")
  vars = {
    id     = local.id
    domain = var.domain
    host   = regex("^(.*):([0-9]+)$", local.value)[0]
    port   = regex("^(.*):([0-9]+)$", local.value)[1]
  }
}

data "template_file" "lmtp_unix_transport" {
  count    = local.delivery == "lmtp-unix" ? 1 : 0
  template = file("${path.module}/mta-exim-transport-${local.delivery}.conf")
  vars = {
    id     = local.id
    domain = var.domain
    socket = local.value
  }
}

output "transport" {
  value = join("", concat(
        data.template_file.lmtp_tcp_transport.*.rendered,
        data.template_file.lmtp_unix_transport.*.rendered))
}
