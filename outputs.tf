# Outputs file
output "app_url" {
  value = "http://${aws_lb.hashiapp.dns_name}"
}

output "ami_id" {
  value = data.hcp_packer_image.ubuntu.cloud_image_id
}