provider "aws" {
  region = var.region
}

resource "aws_instance" "ec2-test" {
  ami           = "ami-04cb4ca688797756f"
  instance_type = "t2.micro"

  tags = {
    Name = "cloudysky-terraform-asg-experiment"
  }
}
