variable "domain" {
}

variable "method" {
}

variable "prefix" {
  default = ""
}

locals {
  id           = "${var.prefix}${replace(var.domain, ".", "_")}"
  method_parts = regex("^([^:]*):(.*)$", var.method)
  delivery     = ( (length(regexall("^lmtp:[^/]*$", var.method)) > 0) ? "lmtp-tcp" :
                   (length(regexall("^lmtp:.*$", var.method)) > 0)    ? "lmtp-unix" :
                   local.method_parts[0])
  value        = local.method_parts[1]
  host         = try(regex("^(.*):([0-9]+)$", local.value)[0], null)
  port         = try(regex("^(.*):([0-9]+)$", local.value)[1], null)
}

output "socket" {
  value = local.delivery == "lmtp-unix" ? local.value : null
}
