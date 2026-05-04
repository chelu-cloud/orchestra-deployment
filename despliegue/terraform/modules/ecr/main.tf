resource "aws_ecr_repository" "ecr-frontend" {
  name                 = "ecr-frontend"
  image_tag_mutability = "IMMUTABLE"  
  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "ecr-backend" {
  name                 = "ecr-backend"
  image_tag_mutability = "IMMUTABLE"  
  image_scanning_configuration {
    scan_on_push = true
  }
}
