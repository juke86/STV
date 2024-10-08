terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = ">= 5.31.0"
    }
  }
}
provider "aws" {
  alias = "east"
  region = "us-east-2"
  profile = "jkennedy"
}
provider "aws" {
  alias = "west"
  region = "us-west-2"
  profile = "jkennedy"
}