variable "region" {
  default = "us-east-1"
}

variable "db_name" {
  default = "mydb"
}

variable "db_username" {
  default = "admin"
}

variable "db_password" {
  default = "password123"
}

variable "instance_type" {
  default = "t3.micro"
}

variable "php_app_ami" {
  description = "AMI for the PHP app"
  default     = "ami-0abcdef1234567890"  # Replace with actual AMI
}