variable "alarm_name_prefix" {}

variable "lb_name" {}

variable "server_min_instances" {}

variable "sns_monitoring_topic_arn" {}

variable "low_priority_sns_monitoring_topic_arn" {}

resource "aws_cloudwatch_metric_alarm" "healthy_hosts_low_too_long" {
  alarm_name = "${var.alarm_name_prefix}:elb:${var.lb_name} Healthy Hosts: Long Deficiency"
  alarm_description = "Less than the desired number of healthy hosts behind this ELB for too long"
  namespace = "AWS/ELB"
  dimensions = {
    "LoadBalancerName" = var.lb_name
  }
  metric_name = "HealthyHostCount"
  comparison_operator = "LessThanThreshold"
  threshold = var.server_min_instances
  unit = "Count"
  period = "300"
  statistic = "Average"
  evaluation_periods = "5"
  alarm_actions = [var.sns_monitoring_topic_arn]
  ok_actions = [var.sns_monitoring_topic_arn]
  insufficient_data_actions = []
}

resource "aws_cloudwatch_metric_alarm" "healthy_hosts_seriously_low" {
  alarm_name = "${var.alarm_name_prefix}:elb:${var.lb_name} Healthy Hosts: Severe Deficiency"
  alarm_description = "Significantly less than the desired number of healthy hosts behind this ELB"
  namespace = "AWS/ELB"
  dimensions = {
    "LoadBalancerName" = var.lb_name
  }
  metric_name = "HealthyHostCount"
  comparison_operator = "LessThanThreshold"
  threshold = var.server_min_instances - 1
  unit = "Count"
  period = "60"
  statistic = "Average"
  evaluation_periods = "3"
  alarm_actions = [var.sns_monitoring_topic_arn]
  ok_actions = [var.sns_monitoring_topic_arn]
  insufficient_data_actions = []
}

resource "aws_cloudwatch_metric_alarm" "latency" {
  alarm_name = "${var.alarm_name_prefix}:elb:${var.lb_name} Latency"
  alarm_description = "High latency from backend servers"
  namespace = "AWS/ELB"
  dimensions = {
    "LoadBalancerName" = var.lb_name
  }
  metric_name = "Latency"
  comparison_operator = "GreaterThanThreshold"
  threshold = "5"
  unit = "Seconds"
  period = "300"
  statistic = "Average"
  evaluation_periods = "3"
  alarm_actions = [var.low_priority_sns_monitoring_topic_arn]
  ok_actions = [var.low_priority_sns_monitoring_topic_arn]
  insufficient_data_actions = []
}

resource "aws_cloudwatch_metric_alarm" "surge_queue" {
  alarm_name = "${var.alarm_name_prefix}:elb:${var.lb_name} Surge Queue Length"
  alarm_description = "ELB has too many requests waiting for a backend instance"
  namespace = "AWS/ELB"
  dimensions = {
    "LoadBalancerName" = var.lb_name
  }
  metric_name = "SurgeQueueLength"
  comparison_operator = "GreaterThanThreshold"
  threshold = "100"
  unit = "Count"
  period = "60"
  statistic = "Maximum"
  evaluation_periods = "1"
  alarm_actions = [var.sns_monitoring_topic_arn]
  ok_actions = [var.sns_monitoring_topic_arn]
  insufficient_data_actions = []
}

resource "aws_cloudwatch_metric_alarm" "spillover" {
  alarm_name = "${var.alarm_name_prefix}:elb:${var.lb_name} Spillover"
  alarm_description = "ELB is rejecting requests due to lack of capacity"
  namespace = "AWS/ELB"
  dimensions = {
    "LoadBalancerName" = var.lb_name
  }
  metric_name = "SpilloverCount"
  comparison_operator = "GreaterThanThreshold"
  threshold = "0"
  unit = "Count"
  period = "60"
  statistic = "Sum"
  evaluation_periods = "1"
  alarm_actions = [var.sns_monitoring_topic_arn]
  ok_actions = [var.sns_monitoring_topic_arn]
  insufficient_data_actions = []
}
