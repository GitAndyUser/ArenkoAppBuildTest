terraform {
  backend "s3" {
    bucket = "terraform-state-bucket"
    key    = "/dev/path/state/terraform.tfstate"
    region = "eu-west-2"
    encrypt = true
  }
}