output "public_ip" {
  value = aws_instance.sdn.public_ip
}

output "instance_id" {
  value = aws_instance.sdn.id
}

output "ssh_command" {
  value = "ssh -i ../ssh/chaves-aws.pem ubuntu@${aws_instance.sdn.public_ip}"
}

output "onos_ui" {
  value = "http://${aws_instance.sdn.public_ip}:8181/onos/ui"
}
