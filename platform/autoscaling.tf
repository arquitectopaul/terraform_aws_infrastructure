provider "aws" {
  region = var.region
}

terraform {
  required_providers {
    aws = {
        source = "hashicorp/aws"
        version = "~> 4.67"
    }
  }
  backend "s3" {
    bucket = "popularsafi-archivos"
    key = "layer2/infrastructure.tfstate"
    region = "us-east-1"
  }
}

data "terraform_remote_state" "network_configuration" {
  backend = "s3"
  config = {
    bucket = var.remote_state_bucket
    key    = var.remote_state_key
    region = var.region
  }
}

data "aws_ami" "launch_configuration_ami" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_iam_role" "ec2_iam_role" {
  name               = "EC2-IAM-Role"
  assume_role_policy = <<EOF
{
  "Version" : "2012-10-17",
  "Statement":
  [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": ["ec2.amazonaws.com", "application-autoscaling.amazonaws.com"]
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "ec2_iam_role_policy" {
  name = "EC2-IAM-Policy"
  role = aws_iam_role.ec2_iam_role.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:*",
        "elasticloadbalancing:*",
        "cloudwatch:*",
        "logs:*"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "EC2-IAM-Instance-Profile"
  role = aws_iam_role.ec2_iam_role.name
}

resource "aws_launch_configuration" "ec2_private_launch_configuration" {
  image_id                    = data.aws_ami.launch_configuration_ami.id
  instance_type               = var.ec2_instance_type
  key_name                    = var.ec2_key_pair_name
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.ec2_instance_profile.name
  security_groups             = [aws_security_group.ec2_private_security_group.id]

  user_data = <<EOF
    #!/bin/bash
    yum update -y
    yum install httpd24 -y
    service httpd start
    chkconfig httpd on
    export INSTANCE_ID=$(curl http://169.254.169.254/latest/meta-data/instance-id)
    echo "<html><body><h1>Hello from Production Backend at instance <b>"$INSTANCE_ID"</b></h1></body></html>" > /var/www/html/index.html
  EOF
}

resource "aws_launch_configuration" "ec2_public_launch_configuration" {
  image_id                    = data.aws_ami.launch_configuration_ami.id
  instance_type               = var.ec2_instance_type
  key_name                    = var.ec2_key_pair_name
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.ec2_instance_profile.name
  security_groups             = [aws_security_group.ec2_public_security_group.id]

  user_data = <<EOF
    #!/bin/bash
    yum update -y
    yum install httpd24 -y
    service httpd start
    chkconfig httpd on
    export INSTANCE_ID=$(curl http://169.254.169.254/latest/meta-data/instance-id)
    echo "<html><body><h1>Hello from Production Web App at instance <b>"$INSTANCE_ID"</b></h1></body></html>" > /var/www/html/index.html
  EOF
}

resource "aws_autoscaling_group" "ec2_private_autoscaling_group" {
  name                  = "Production-Backend-AutoScalingGroup"
  vpc_zone_identifier   = [
    data.terraform_remote_state.network_configuration.outputs.private-subnet-1_id,
    data.terraform_remote_state.network_configuration.outputs.private-subnet-2_id,
    data.terraform_remote_state.network_configuration.outputs.private-subnet-3_id
  ]
  max_size              = var.ec2_max_instance_size
  min_size              = var.ec2_min_instance_size
  launch_configuration  = aws_launch_configuration.ec2_private_launch_configuration.name
  health_check_type     = "ELB"
  load_balancers        = [aws_elb.backend-load-balancer.name]

  tag {
    key                 = "Name"
    propagate_at_launch = true
    value               = var.tag_production
  }

  tag {
    key                 = "Type"
    propagate_at_launch = true
    value               = var.tag_backend
  }
}

resource "aws_autoscaling_group" "ec2_public_autoscaling_group" {
  name                  = "Production-WebApp-AutoScalingGroup"
  vpc_zone_identifier   = [
    data.terraform_remote_state.network_configuration.outputs.public-subnet-1_id,
    data.terraform_remote_state.network_configuration.outputs.public-subnet-2_id,
    data.terraform_remote_state.network_configuration.outputs.public-subnet-3_id
  ]
  max_size              = var.ec2_max_instance_size
  min_size              = var.ec2_min_instance_size
  launch_configuration  = aws_launch_configuration.ec2_public_launch_configuration.name
  health_check_type     = "ELB"
  load_balancers        = [aws_elb.webapp-load-balancer.name]

  tag {
    key                 = "Name"
    propagate_at_launch = true
    value               = var.tag_production
  }

  tag {
    key                 = "Type"
    propagate_at_launch = true
    value               = var.tag_webapp
  }
}

data "aws_instances" "web-app-production-instances" {
  instance_tags = {
    Type = var.tag_webapp
  }
  filter {
    name   = "instance.group-id"
    values = [aws_security_group.ec2_public_security_group.id]
  }

  instance_state_names = [ "running", "stopped" ]
  depends_on           = [aws_autoscaling_group.ec2_public_autoscaling_group]
}

data "aws_instances" "backend-production-instances" {
  instance_tags = {
    Type = var.tag_backend
  }
  filter {
    name   = "instance.group-id"
    values = [aws_security_group.ec2_private_security_group.id]
  }

  instance_state_names = [ "running", "stopped" ]
  depends_on           = [aws_autoscaling_group.ec2_private_autoscaling_group]
}


resource "aws_autoscaling_policy" "webapp-production-scale-up-policy" {
  autoscaling_group_name   = aws_autoscaling_group.ec2_public_autoscaling_group.name
  name                     = "Production-WebApp-AutoScaling-Policy"
  policy_type              = "TargetTrackingScaling"
  min_adjustment_magnitude = 1

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 80.0
  }
}
