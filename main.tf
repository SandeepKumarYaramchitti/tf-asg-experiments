provider "aws" {
  region = var.region
}

data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "2.77.0"
  name    = "main-vpc"
  cidr    = "10.0.0.0/16"

  azs                  = data.aws_availability_zones.available.names
  public_subnets       = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
  enable_dns_hostnames = true
  enable_dns_support   = true
}

data "aws_ami" "amazon-linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-kernel-6.1-x86_64"]
  }
}

# amzn-ami-hvm-2018.03.0.20230905.0-x86_64-ebs

# al2023-ami-2023.2.20230920.1-kernel-6.1-x86_64

resource "aws_iam_instance_profile" "codedeploy_ec2_profile" {
  name = "codedeploy-instance-profile"
  role = aws_iam_role.codedeploy_role.name
}



resource "aws_launch_configuration" "terramino" {
  name_prefix          = "learn-terraform-aws-asg-"
  iam_instance_profile = aws_iam_instance_profile.codedeploy_ec2_profile.name
  # iam_instance_profile = aws_iam_instance_profile.codedeploy_ec2_profile.name
  image_id        = data.aws_ami.amazon-linux.id
  instance_type   = "t2.micro"
  key_name        = "asg-key-pair"
  user_data       = file("user-data.sh")
  security_groups = [aws_security_group.terramino_instance.id]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "terramino" {
  name                 = "terramino"
  min_size             = 1
  max_size             = 3
  desired_capacity     = 2
  launch_configuration = aws_launch_configuration.terramino.name
  vpc_zone_identifier  = module.vpc.public_subnets

  health_check_type = "ELB"

  tag {
    key                 = "Name"
    value               = "HashiCorp Learn ASG - Terramino"
    propagate_at_launch = true
  }
}

# Autoscaling life cycle hooks
resource "aws_autoscaling_lifecycle_hook" "asg_life_cycle_hook" {
  name                   = "asg-life-cycle-hook"
  autoscaling_group_name = aws_autoscaling_group.terramino.name
  default_result         = "CONTINUE"
  heartbeat_timeout      = 2000
  lifecycle_transition   = "autoscaling:EC2_INSTANCE_LAUNCHING"
  # notification_target_arn = aws_sns_topic.my_sns_topic.arn
  # Replace notification arn to lambda function arn
  notification_target_arn = aws_lambda_function.asg_lifecycle_hook.arn
  role_arn                = aws_iam_role.cw_to_sns_role.arn
}

# Set up a SNS topic name
resource "aws_sns_topic" "my_sns_topic" {
  name = "my_sns_topic"
}

# Create a subscription to the SNS topic
resource "aws_sns_topic_subscription" "my_sns_topic_subscription" {
  topic_arn = aws_sns_topic.my_sns_topic.arn
  protocol  = "email"
  endpoint  = "ysandeepkumar88@gmail.com"
}




# Create Cloudwatch event rule that will watch for EC2 to get into life cycle hook
resource "aws_cloudwatch_event_rule" "asg_lifecycle_event" {
  name        = "asg-lifecycle-event"
  description = "Watch for EC2 to get into life cycle hook"
  event_pattern = jsonencode({
    source      = ["aws.autoscaling"]
    detail_type = ["EC2 Instance-launch Lifecycle Action"]
    detail = {
      AutoScalingGroupName = [aws_autoscaling_group.terramino.name]
    }
  })
}

# Create a target for the event rule
resource "aws_cloudwatch_event_target" "asg_lifecycle_event_target" {
  rule = aws_cloudwatch_event_rule.asg_lifecycle_event.name
  arn  = aws_sns_topic.my_sns_topic.arn
  input_transformer {
    input_paths = {
      instance_id = "$.detail.EC2InstanceId"
    }
    input_template = "\"Instance with ID <instance_id> entered the lifecycle hook.\""
  }
}

resource "aws_iam_role" "cw_to_sns_role" {
  name = "CloudWatchToSNSTopicRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = ["events.amazonaws.com", "autoscaling.amazonaws.com"]
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "cw_to_sns_policy" {
  name = "CloudWatchToSNSTopicPolicy"
  role = aws_iam_role.cw_to_sns_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action   = "sns:Publish",
        Effect   = "Allow",
        Resource = aws_sns_topic.my_sns_topic.arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "invoke_lambda_from_asg" {
  name = "InvokeLambdaFromASG"
  role = aws_iam_role.cw_to_sns_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action   = "lambda:InvokeFunction",
        Effect   = "Allow",
        Resource = aws_lambda_function.asg_lifecycle_hook.arn
      }
    ]
  })
}


# resource "aws_iam_role_policy_attachment" "cw_to_sns_policy_attachment" {
#   role       = aws_iam_role.cw_to_sns_role.id
#   policy_arn = "arn:aws:iam::aws:policy/service-role/AutoScalingNotificationAccessRole"
# }


# resource "aws_iam_role_policy" "cw_to_sns_policy" {
#   name = "CloudWatchToSNSTopicPolicy"
#   role = aws_iam_role.cw_to_sns_role.id

#   policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Action   = "sns:Publish",
#         Effect   = "Allow",
#         Resource = aws_sns_topic.asg_lifecycle_topic.arn
#       }
#     ]
#   })
# }

resource "aws_lb" "terramino" {
  name               = "learn-asg-terramino-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.terramino_lb.id]
  subnets            = module.vpc.public_subnets
}

resource "aws_lb_listener" "terramino" {
  load_balancer_arn = aws_lb.terramino.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.terramino.arn
  }
}

resource "aws_lb_target_group" "terramino" {
  name     = "learn-asg-terramino"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id
}


resource "aws_autoscaling_attachment" "terramino" {
  depends_on             = [aws_autoscaling_group.terramino, aws_lb_target_group.terramino]
  autoscaling_group_name = aws_autoscaling_group.terramino.id
  alb_target_group_arn   = aws_lb_target_group.terramino.arn
}

resource "aws_security_group" "terramino_instance" {
  name = "learn-asg-terramino-instance"

  # Port 22 for SSH
  # ingress {
  #   from_port   = 22
  #   to_port     = 22
  #   protocol    = "tcp"
  #   cidr_blocks = ["0.0.0.0/0"]
  # }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }



  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.terramino_lb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  vpc_id = module.vpc.vpc_id
}

resource "aws_security_group" "terramino_lb" {
  name = "learn-asg-terramino-lb"
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }



  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  vpc_id = module.vpc.vpc_id
}

# S3 Bucket for CodeDeploy deployment packages
resource "aws_s3_bucket" "codedeploy_bucket" {
  bucket = "cloudysky-codedeploy-bucket"
  acl    = "private"
}

# CodeDeploy Application
resource "aws_codedeploy_app" "app" {
  name = "my-codedeploy-app"
}

# CodeDeploy Deployment Group
resource "aws_codedeploy_deployment_group" "dg" {
  app_name              = aws_codedeploy_app.app.name
  deployment_group_name = "my-deployment-group"
  service_role_arn      = aws_iam_role.codedeploy_role.arn
  autoscaling_groups    = [aws_autoscaling_group.terramino.name]

  deployment_config_name = "CodeDeployDefault.OneAtATime"

  # Configure the load balancer for Blue/Green deployments (optional)
  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route {
        listener_arns = [aws_lb_listener.terramino.arn]
      }

      target_group {
        name = aws_lb_target_group.terramino.name
      }
    }
  }
}

# IAM Role for CodeDeploy
resource "aws_iam_role" "codedeploy_role" {
  name = "codedeploy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = ["codedeploy.amazonaws.com", "ec2.amazonaws.com"]
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "codedeploy_policy_attachment" {
  role       = aws_iam_role.codedeploy_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole"
}

resource "aws_iam_policy" "s3_access_for_codedeploy" {
  name        = "S3AccessForCodeDeploy"
  description = "Policy that grants access to S3 bucket for CodeDeploy"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ],
        Effect = "Allow",
        Resource = [
          "arn:aws:s3:::cloudysky-codedeploy-bucket",
          "arn:aws:s3:::cloudysky-codedeploy-bucket/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "s3_access_attachment_for_codedeploy" {
  role       = aws_iam_role.codedeploy_role.name
  policy_arn = aws_iam_policy.s3_access_for_codedeploy.arn
}

# Zip the lambda function
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "lambda-src/handler.py"
  output_path = "lambda-src/lambda.zip"
}

# resource "aws_iam_role" "lambda_role" {
#   name = "my_lambda_function_role"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Action = "sts:AssumeRole",
#         Effect = "Allow",
#         Principal = {
#           Service = "lambda.amazonaws.com"
#         }
#       }
#     ]
#   })
# }

resource "aws_iam_role" "lambda_execution_role" {
  name = "lambda_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = ["lambda.amazonaws.com", "autoscaling.amazonaws.com"]
        }
      }
    ]
  })
}

# Create Lambda function
resource "aws_lambda_function" "asg_lifecycle_hook" {
  function_name = "asg_lifecycle_hook"
  role          = aws_iam_role.lambda_execution_role.arn
  handler       = "handler.handler" # Assuming the handler function in your handler.py is named "handler"

  filename = data.archive_file.lambda_zip.output_path

  runtime = "python3.8" # Update to the desired Python version

  # Optional: set environment variables for the Lambda function
  # environment {
  #   variables = {
  #     foo = "bar"
  #   }
  # }
}

















