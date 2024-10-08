# Create VPC
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.13.0"
  name    = "php-app-vpc"
  cidr    = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.3.0/24", "10.0.4.0/24"]

  enable_nat_gateway = true
}

# Security Group for EC2 instances
resource "aws_security_group" "php_app_sg" {
  vpc_id = module.vpc.vpc_id

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
}

# Security Group for Aurora DB
resource "aws_security_group" "db_sg" {
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]  # Limit access to VPC range
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Aurora MySQL DB Cluster
resource "aws_rds_cluster" "aurora" {
  cluster_identifier = "aurora-cluster"
  engine             = "aurora-mysql"
  engine_version     = "5.7.mysql_aurora.2.08.1"
  master_username    = var.db_username
  master_password    = var.db_password
  database_name      = var.db_name
  skip_final_snapshot = true
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.main.id
}

resource "aws_db_subnet_group" "main" {
  name       = "aurora-subnet-group"
  subnet_ids = module.vpc.private_subnets
}

# Launch Template for Auto Scaling Group
resource "aws_launch_template" "php_app" {
  name_prefix = "php-app"

  image_id      = var.php_app_ami
  instance_type = var.instance_type
  security_group_ids = [aws_security_group.php_app_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              sudo yum install -y httpd php mysql
              echo "<?php phpinfo(); ?>" > /var/www/html/index.php
              sudo systemctl start httpd
              sudo systemctl enable httpd
              EOF
}

# Auto Scaling Group
resource "aws_autoscaling_group" "php_app_asg" {
  launch_template {
    id      = aws_launch_template.php_app.id
    version = "$Latest"
  }

  vpc_zone_identifier         = module.vpc.public_subnets
  min_size                    = 1
  max_size                    = 3
  desired_capacity            = 1
  health_check_type           = "EC2"
  health_check_grace_period   = 300

  tag {
    key                 = "Name"
    value               = "php-app-instance"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Load Balancer
resource "aws_lb" "php_app_lb" {
  name               = "php-app-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.php_app_sg.id]
  subnets            = module.vpc.public_subnets
}

# Target Group for Load Balancer
resource "aws_lb_target_group" "php_app_tg" {
  name     = "php-app-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id

  health_check {
    path                = "/"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 5
    unhealthy_threshold = 2
  }
}

# Listener for Load Balancer
resource "aws_lb_listener" "php_app_listener" {
  load_balancer_arn = aws_lb.php_app_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.php_app_tg.arn
  }
}

# Auto Scaling Target Group Attachment
resource "aws_autoscaling_attachment" "asg_attachment" {
  autoscaling_group_name = aws_autoscaling_group.php_app_asg.id
  alb_target_group_arn   = aws_lb_target_group.php_app_tg.arn
}

# CloudWatch Monitoring for Load Balancer and Latency
resource "aws_cloudwatch_metric_alarm" "request_count_alarm" {
  alarm_name          = "HighRequestCount"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "RequestCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 100  # Change as per need

  dimensions = {
    LoadBalancer = aws_lb.php_app_lb.name
  }

  alarm_actions = [aws_sns_topic.php_app_alarm.arn]
}

resource "aws_cloudwatch_metric_alarm" "latency_alarm" {
  alarm_name          = "HighLatencyAlarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 2.0  # Threshold for high latency

  dimensions = {
    LoadBalancer = aws_lb.php_app_lb.name
  }

  alarm_actions = [aws_sns_topic.php_app_alarm.arn]
}

# SNS Topic for Alarms
resource "aws_sns_topic" "php_app_alarm" {
  name = "php-app-alarms"
}

resource "aws_sns_topic_subscription" "php_app_alarm_subscription" {
  topic_arn = aws_sns_topic.php_app_alarm.arn
  protocol  = "email"
  endpoint  = "your-email@example.com"  # Change to your email
}