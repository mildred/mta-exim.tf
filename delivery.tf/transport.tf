output "transport" {
  value = templatefile("${path.module}/mta-exim-transport-${local.delivery}.conf", {
    id       = local.id
    delivery = local.delivery

    # If lmtp-tcp
    host     = local.host
    port     = local.port

    # If lmtp-unix
    socket   = local.value
  })
}
