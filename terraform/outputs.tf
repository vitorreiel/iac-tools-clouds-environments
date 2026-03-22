output "configured_host" {
  value = var.ec2_public_ip
}

output "onos_ui" {
  value = "http://${var.ec2_public_ip}:8181/onos/ui"
}
