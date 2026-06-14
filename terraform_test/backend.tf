#set up a remote state file so code can be executed by any admins. 
#added KMS key so it can be run by dev teams. 

terraform {
  backend "s3" {
    bucket = "terraform-state-bucket"
    key    = "/dev/path/state/terraform.tfstate"
    region = "eu-west-2"
    encrypt = true
    kms_key_id = "arn:aws:kms:eu-west-2:123456789012:key/blah-1234..."
  }
}
