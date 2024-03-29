output "app_url" {
  description = "URL of the deployed webapp."
  value       = "http://${aws_eip.hashicafe.public_dns}"
}

output "ami_id" {
  description = "ID of the AMI resolved from HCP Packer."
  value       = aws_instance.hashicafe.ami
}

output "product" {
  description = "The product which was randomly selected."
  value       = var.hashi_products[random_integer.product.result].name
}
