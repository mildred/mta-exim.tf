output "router" {
  value = templatefile("${path.module}/mta-exim-router-${local.delivery}.conf", {
    id       = local.id
    delivery = local.delivery
    domain   = var.domain

    # If lmtp-tcp
    host     = local.host
    port     = local.port

    # If lmtp-unix
    socket   = local.value
  })
}
