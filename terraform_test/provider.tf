#provider details, but normally companies prefer the eu-west-1 in Ireland because of the cost optimisation of saving ~5% also the same security and regulatory scope. 
provider "aws" {
  region = $(var.aws_region)
}