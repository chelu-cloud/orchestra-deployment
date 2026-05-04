resource "aws_db_subnet_group" "subnet_group" {
  name       = "main_db_subnet_group"
  subnet_ids = var.private_data_subnet_ids

  tags = {
    Name = "My DB private subnet group"
  }
}

resource "aws_db_instance" "db-rds" {
  allocated_storage      = 10
  identifier             = "postgres-test2"
  db_subnet_group_name   = aws_db_subnet_group.subnet_group.id
  engine                 = "postgres"
  engine_version         = "14"
  instance_class         = "db.t3.micro"
  username               = "postgres"

  manage_master_user_password = true // AWS maneja la rotación de contraseñas

  // La app consulta el Secret Manager API en runtime. Con el ARN del secret hace la consulta y obtiene las credenciales.

  vpc_security_group_ids = [var.db_security_group_id]
  publicly_accessible    = false
  skip_final_snapshot    = true
}