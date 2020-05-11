variable "alb_dimension_id" {}

variable "target_group_dimension_id" {}

variable "app_environment" {}

variable "targets_name" {}

variable "server_min_instances" {}

variable "server_min_healthy_instances" {}

variable "sns_monitoring_topic_arn" {}

variable "low_priority_sns_monitoring_topic_arn" {}

variable "treat_missing_data" {
  default = "missing"
}

resource "aws_cloudwatch_metric_alarm" "healthy_hosts_low_too_long" {
  alarm_name = "${var.app_environment}:alb:public:${var.targets_name} Healthy Hosts: Long Deficiency"
  alarm_description = "Less than the desired number of healthy ${var.targets_name} hosts behind the ALB for too long"
  namespace = "AWS/ApplicationELB"
  dimensions = {
    "LoadBalancer" = var.alb_dimension_id
    "TargetGroup" = var.target_group_dimension_id
  }
  metric_name = "HealthyHostCount"
  comparison_operator = "LessThanThreshold"
  threshold = var.server_min_instances
  unit = "Count"
  period = "300"
  statistic = "Average"
  evaluation_periods = "12"
  alarm_actions = [var.sns_monitoring_topic_arn]
  ok_actions = [var.sns_monitoring_topic_arn]
  insufficient_data_actions = []
}

resource "aws_cloudwatch_metric_alarm" "healthy_hosts_seriously_low" {
  alarm_name = "${var.app_environment}:alb:public:${var.targets_name} Healthy Hosts: Severe Deficiency"
  alarm_description = "Significantly less than the desired number of healthy ${var.targets_name} hosts behind the ALB"
  namespace = "AWS/ApplicationELB"
  dimensions = {
    "LoadBalancer" = var.alb_dimension_id
    "TargetGroup" = var.target_group_dimension_id
  }
  metric_name = "HealthyHostCount"
  comparison_operator = "LessThanThreshold"
  threshold = var.server_min_healthy_instances
  unit = "Count"
  period = "60"
  statistic = "Average"
  evaluation_periods = "3"
  alarm_actions = [var.sns_monitoring_topic_arn]
  ok_actions = [var.sns_monitoring_topic_arn]
  insufficient_data_actions = []
}

resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts_too_many_too_long" {
  alarm_name = "${var.app_environment}:alb:public:${var.targets_name} Unhealthy Hosts: Too many"
  alarm_description = "Too many unhealthy hosts in ${var.targets_name} behind the ALB. This should not be triggered by normal autoscaling and deployment"
  namespace = "AWS/ApplicationELB"
  dimensions = {
    "LoadBalancer" = var.alb_dimension_id
    "TargetGroup" = var.target_group_dimension_id
  }

  metric_name = "UnHealthyHostCount"
  comparison_operator = "GreaterThanThreshold"
  threshold = "1"
  unit = "Count"
  period = "60"
  statistic = "Average"
  evaluation_periods = "3"

  alarm_actions = [var.sns_monitoring_topic_arn]
  ok_actions = [var.sns_monitoring_topic_arn]
  insufficient_data_actions = []
}

resource "aws_cloudwatch_metric_alarm" "target_response_time" {
  alarm_name = "${var.app_environment}:alb:public:${var.targets_name} Target Response Time (Latency)"
  alarm_description = "High latency from backend servers"
  namespace = "AWS/ApplicationELB"
  dimensions = {
    "LoadBalancer" = var.alb_dimension_id
    "TargetGroup" = var.target_group_dimension_id
  }
  metric_name = "TargetResponseTime"
  comparison_operator = "GreaterThanThreshold"
  threshold = "5"
  unit = "Seconds"
  period = "300"
  statistic = "Average"
  evaluation_periods = "3"
  alarm_actions = [var.low_priority_sns_monitoring_topic_arn]
  ok_actions = [var.low_priority_sns_monitoring_topic_arn]
  insufficient_data_actions = []
  treat_missing_data = var.treat_missing_data
}

resource "aws_cloudwatch_metric_alarm" "rejected_connection_count" {
  alarm_name = "${var.app_environment}:alb:public:${var.targets_name} Rejected Connection Count"
  alarm_description = "Connections rejected for lack of a healthy target"
  namespace = "AWS/ApplicationELB"
  dimensions = {
    "LoadBalancer" = var.alb_dimension_id
    "TargetGroup" = var.target_group_dimension_id
  }
  metric_name = "RejectedConnectionCount"
  comparison_operator = "GreaterThanThreshold"
  threshold = "0"
  unit = "Count"
  period = "60"
  statistic = "Sum"
  evaluation_periods = "1"
  alarm_actions = [var.sns_monitoring_topic_arn]
  ok_actions = [var.sns_monitoring_topic_arn]
  insufficient_data_actions = []
  treat_missing_data = "notBreaching"
}
