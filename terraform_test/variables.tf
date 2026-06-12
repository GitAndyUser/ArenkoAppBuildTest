# Added type to original code to make it more readable. 
variable "environment" {
  description = "the environment name"
  type        = string
}

variable "service" {
  description = "the service name"
  type        = string
}

variable "desired_num_nginx" {
  description = "the service name"
  type        = number
}

variable "desired_num_app" {
  description = "the service name"
  type        = number
}

/*
 Suggestion for the future, make longer lists of input variables for example many AZ, the AZ is made up bad example to demonstrate list of variables.
variable "AZ_list" {
  description = "AZs to be used" 
  type = list(string)
}

then in the main.tf or appropriate area when specifying AZs 
for_each = toset(var.AZ_list)
*/