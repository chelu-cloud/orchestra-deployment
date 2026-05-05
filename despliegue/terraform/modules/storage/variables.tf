variable "private_data_subnet_ids" {
  description = "List if ids to use into subnetgroups"
  type        = list(string)
}

variable "db_security_group_id" {
  description = "DB sec group ID"
  type        = string
}

variable "kms_key_id" {
    description = "Pass key of db"
    type = string
    default = "db-pass"
}