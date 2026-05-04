variable "cidr_block_vpc_a" {
  type = string
  default = "10.0.0.0/16"
}

variable "public_subnet_cidr_a" {
    description = "Public subnets vpc A: CIDR_BLOCKS"
    type = list(string)
    default = [ "10.0.1.0/24","10.0.2.0/24" ]
}

variable "private_subnet_cidr_a_app" {
    description = "Private subnets vpc A: CIDR_BLOCKS"
    type = list(string)
    default = [ "10.0.3.0/24","10.0.4.0/24" ]
}

variable "private_subnet_cidr_a_data" {
    description = "Private subnets vpc A: CIDR_BLOCKS"
    type = list(string)
    default = [ "10.0.5.0/24","10.0.6.0/24" ]
}

variable "az" {
    type = list(string)
    default = [ "eu-west-3a", "eu-west-3b" ]
}