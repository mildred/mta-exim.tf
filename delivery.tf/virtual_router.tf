variable "virtual_json_file" {
  default = ""
}

variable "sockapi" {
  default = ""
}

output "virtual_router" {
  value = templatefile("${path.module}/mta-exim-virtual-router-${local.delivery}.conf", {
    id           = local.id
    delivery     = local.delivery
    domain       = var.domain
    virtual_json = var.virtual_json_file
    sockapi      = var.sockapi

    # If lmtp-tcp
    host     = local.host
    port     = local.port

    # If lmtp-unix
    socket   = local.value
  })
}
