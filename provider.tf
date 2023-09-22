terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.38"
    }
  }

  required_version = ">= 0.15"

  cloud {
    organization = "cloudysky"

    workspaces {
      name = "terraform-asg-experiment"
    }
  }
}
