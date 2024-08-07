variable "prefix" {
  type        = string
  description = "This prefix will be included in the name of most resources."
}

variable "region" {
  type        = string
  description = "The region where the resources are created."
  default     = "us-east-2"
}

variable "env" {
  type        = string
  description = "Value for the environment tag."
}

variable "department" {
  description = "Value for the department tag."
  type        = string
  default     = "WebDev"
}

variable "owner" {
  description = "Value for the owner tag."
  type        = string
  default     = "web.developer"
}

variable "extra_tags" {
  description = "Additional tags to add to resources."
  type        = map(string)
  default     = {}
}

variable "address_space" {
  type        = string
  description = "The address space that is used by the virtual network. You can supply more than one address space. Changing this forces a new resource to be created."
  default     = "10.0.0.0/16"
}

variable "subnet_prefix" {
  type        = string
  description = "The address prefix to use for the subnet."
  default     = "10.0.10.0/24"
}

variable "instance_type" {
  type        = string
  description = "Specifies the AWS instance type."
  default     = "t3.micro"
}

variable "packer_bucket" {
  type        = string
  description = "HCP Packer bucket name containing the source image."
  default     = "ubuntu22-nginx"
}

variable "packer_channel" {
  type        = string
  description = "HCP Packer image channel."
  default     = "production"
}

variable "hashi_products" {
  type = list(object({
    name       = string
    color      = string
    image_file = string
  }))
  default = [
    {
      name       = "Consul"
      color      = "#dc477d"
      image_file = "hashicafe_art_consul.png"
    },
    {
      name       = "HCP"
      color      = "#ffffff"
      image_file = "hashicafe_art_hcp.png"
    },
    {
      name       = "Nomad"
      color      = "#60dea9"
      image_file = "hashicafe_art_nomad.png"
    },
    {
      name       = "Packer"
      color      = "#63d0ff"
      image_file = "hashicafe_art_packer.png"
    },
    {
      name       = "Terraform"
      color      = "#844fba"
      image_file = "hashicafe_art_terraform.png"
    },
    {
      name       = "Vagrant"
      color      = "#2e71e5"
      image_file = "hashicafe_art_vagrant.png"
    },
    {
      name       = "Vault"
      color      = "#ffec6e"
      image_file = "hashicafe_art_vault.png"
    }
  ]
}
