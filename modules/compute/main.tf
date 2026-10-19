data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
}

resource "aws_launch_template" "app" {
  image_id      = data.aws_ssm_parameter.al2023.value
  user_data     = filebase64("${path.module}/user_data.sh")
  instance_type = var.instance_type
  iam_instance_profile {
    name = var.ec2_instance_profile_name
  }
  vpc_security_group_ids = [var.ec2_security_group_ids]

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }
  tag_specifications {
    resource_type = "instance"
    tags = {
      "Name" = "production-platform-app"
    }
  }
}

resource "aws_autoscaling_group" "app" {

  desired_capacity          = 2
  min_size                  = 2
  max_size                  = 3
  health_check_type         = "ELB"
  health_check_grace_period = 300
  target_group_arns         = var.target_group_arns
  vpc_zone_identifier       = var.private_subnet_ids
  launch_template {
    id      = aws_launch_template.app.id
    version = aws_launch_template.app.latest_version
  }
  tag {
    key                 = "Name"
    value               = "production-platform-app"
    propagate_at_launch = true
  }
  tag {
    key                 = "Environment"
    value               = "lab"
    propagate_at_launch = true
  }
  tag {
    key                 = "Project"
    value               = "AWS_Platform_IaC"
    propagate_at_launch = true
  }

  lifecycle {
    ignore_changes = [desired_capacity]
  }
}

resource "aws_autoscaling_policy" "cpu_target_tracking" {
  name                   = "cpu_target_tracking"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"
  target_tracking_configuration {
    target_value = 60
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
  }
}
