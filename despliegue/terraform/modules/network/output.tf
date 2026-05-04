output "private_data_subnet_ids"{
    description = "Ids list of data private subnets"
    value = aws_subnet.a_subnet_private_data[*].id
}

output "private_app_subnet_ids" {
    description = "Ids of the eks subnets"
    value = aws_subnet.a_subnet_private_app[*].id
}

output "private_sg_id_db"{
    description = "Ids list of sgroups"
    value = aws_security_group.data-base.id
}

