terraform {
  backend "s3" {
    bucket = "orchestra-bucket-622370466117-eu-west-3-an"
    key    = "proyect/proyect.tfstate"
    region = "eu-west-3"
  }
}