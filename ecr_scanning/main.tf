variable "aws_region" {}

variable "slack_channel" {
  description = "The slack channel to send notifications to, prefixed with '#'"
}

variable "findings_slack_notification_url" {
  description = "The slack webhook URL to send notifications to"
}

variable "lambda_errors_sns_topic_name" {
  description = "SNS topic's name where alarms for errors on the notifying Lambda should be sent"
}

variable "ecr_repositories_to_scan_daily" {
  description = "A list of names of the ECR repositories to scan daily for vulnerabilities"
  type = list(string)
}

variable "tags_to_scan" {
  description = "A list of tags identifying the images that are scanned daily for vulnerabilities"
  type = list(string)
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "allow_lambda_to_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "archive_file" "ecr_scan_result_lambda_zip" {
  type = "zip"
  source_file = "${path.module}/templates/process-ecr-scan-result.rb"
  output_path = "${path.module}/templates/process-ecr-scan-result.zip"
}

resource "aws_iam_role" "ecr_scan_result_lambda_role" {
  name = "ecrScanResultToSlackRole"
  description = "Used to route ECR vulnerability scan results to the ControlShift team slack"
  assume_role_policy = data.aws_iam_policy_document.allow_lambda_to_assume_role.json
}

resource "aws_lambda_function" "ecr_scan_result_to_slack" {
  filename = data.archive_file.ecr_scan_result_lambda_zip.output_path
  function_name = "ecrScanResultsToSlack"
  role = aws_iam_role.ecr_scan_result_lambda_role.arn
  runtime = "ruby3.2"
  timeout = 60

  source_code_hash = data.archive_file.ecr_scan_result_lambda_zip.output_base64sha256
  handler = "process-ecr-scan-result.handler"

  environment {
    variables = {
      SLACK_CHANNEL = var.slack_channel
      SLACK_WEBHOOK_URL = var.findings_slack_notification_url
      SUPPRESS_MESSAGES_WITH_NO_VULNERABILITIES = "true"
    }
  }
}

resource "aws_cloudwatch_log_group" "ecr_scan_result_lambda" {
  name = "/aws/lambda/${aws_lambda_function.ecr_scan_result_to_slack.function_name}"
  retention_in_days = 5
}

data "aws_iam_policy_document" "ecr_scan_result_lambda_logging" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:${aws_cloudwatch_log_group.ecr_scan_result_lambda.name}:*"
    ]
  }
}

resource "aws_iam_policy" "ecr_scan_result_lambda_logging" {
  name = "ecr-scan-result-to-slack-lambda-logging"
  description = "Allow the lambda function to write logs to CloudWatch"
  policy = data.aws_iam_policy_document.ecr_scan_result_lambda_logging.json
}

resource "aws_iam_role_policy_attachment" "ecr_scan_result_lambda_logging" {
  role = aws_iam_role.ecr_scan_result_lambda_role.name
  policy_arn = aws_iam_policy.ecr_scan_result_lambda_logging.arn
}

data "aws_sns_topic" "lambda_errors" {
  name = var.lambda_errors_sns_topic_name
}

resource "aws_cloudwatch_metric_alarm" "ecr_scan_result_lambda_errors" {
  alarm_name = "lambda:${aws_lambda_function.ecr_scan_result_to_slack.function_name} Errors"
  alarm_description = "Lambda function ${aws_lambda_function.ecr_scan_result_to_slack.function_name} raised more than one exception in 10 minutes"
  dimensions = {
    FunctionName = aws_lambda_function.ecr_scan_result_to_slack.function_name
  }
  namespace = "AWS/Lambda"
  metric_name = "Errors"

  # Alert if the function raises an error more than once in a 10-minute period
  # Q: Why more than once? Won't this miss some errors?
  # A: Lambda automatically retries function errors twice. For a given invocation, the function will be
  #    attempted 3 times before it gives up. Alerting on the second exception should catch persistent errors,
  #    while avoiding noise from temporary network glitches.
  statistic = "Sum"
  period = 600
  comparison_operator = "GreaterThanThreshold"
  threshold = 1
  evaluation_periods = 1

  treat_missing_data = "notBreaching"
  alarm_actions = [data.aws_sns_topic.lambda_errors.arn]
  ok_actions = [data.aws_sns_topic.lambda_errors.arn]
  insufficient_data_actions = []
}

resource "aws_cloudwatch_event_rule" "ecr_scan_completed" {
  name = "ecr-scan-completed"
  description = "An ECR image has been scanned for vulnerabilities"

  event_pattern = jsonencode({
    source = ["aws.ecr"],
    detail-type = ["ECR Image Scan"],
    detail = {
      scan-status = ["COMPLETE"]
    }
  })
}

resource "aws_cloudwatch_event_target" "ecr_scan_result_lambda" {
  target_id = "SendEcrScanResultsToLambda"
  arn  = aws_lambda_function.ecr_scan_result_to_slack.arn
  rule = aws_cloudwatch_event_rule.ecr_scan_completed.id
}

resource "aws_lambda_permission" "allow_event_to_trigger_ecr_scan_result_lambda" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ecr_scan_result_to_slack.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ecr_scan_completed.arn
}

data "archive_file" "start_ecr_scans_lambda_zip" {
  type = "zip"
  source_file = "${path.module}/templates/start-ecr-scans.rb"
  output_path = "${path.module}/templates/start-ecr-scans.zip"
}

resource "aws_iam_role" "start_ecr_scans_lambda_role" {
  name = "startEcrScansLambdaRole"
  description = "Used to schedule daily manual scans of docker images in ECR"
  assume_role_policy = data.aws_iam_policy_document.allow_lambda_to_assume_role.json
}

resource "aws_cloudwatch_log_group" "start_ecr_scans_lambda" {
  name = "/aws/lambda/${aws_lambda_function.start_ecr_scans.function_name}"
  retention_in_days = 5
}

data "aws_iam_policy_document" "start_ecr_scans_lambda_logging" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:${aws_cloudwatch_log_group.start_ecr_scans_lambda.name}:*"
    ]
  }
}

resource "aws_iam_policy" "start_ecr_scans_lambda_logging" {
  name = "start-ecr-scans-lambda-logging"
  description = "Allow the lambda function to write logs to CloudWatch"
  policy = data.aws_iam_policy_document.start_ecr_scans_lambda_logging.json
}

resource "aws_iam_role_policy_attachment" "start_ecr_scans_lambda_logging" {
  role = aws_iam_role.start_ecr_scans_lambda_role.name
  policy_arn = aws_iam_policy.start_ecr_scans_lambda_logging.arn
}

data "aws_iam_policy_document" "start_ecr_scans_lambda_ecr_operations" {
  statement {
    effect = "Allow"
    actions = [
      "ecr:DescribeImages",
      "ecr:StartImageScan"
    ]
    resources = [
      "arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/*"
    ]
  }
}

resource "aws_iam_policy" "start_ecr_scans_lambda_ecr_operations" {
  name = "start-ecr-scans-lambda-ecr-operations"
  description = "Allow the lambda function to look for ECR images and start scans"
  policy = data.aws_iam_policy_document.start_ecr_scans_lambda_ecr_operations.json
}

resource "aws_iam_role_policy_attachment" "start_ecr_scans_lambda_ecr_operations" {
  role = aws_iam_role.start_ecr_scans_lambda_role.name
  policy_arn = aws_iam_policy.start_ecr_scans_lambda_ecr_operations.arn
}

resource "aws_lambda_function" "start_ecr_scans" {
  filename = data.archive_file.start_ecr_scans_lambda_zip.output_path
  function_name = "startEcrScans"
  role = aws_iam_role.start_ecr_scans_lambda_role.arn
  runtime = "ruby3.2"
  timeout = 60

  source_code_hash = data.archive_file.start_ecr_scans_lambda_zip.output_base64sha256
  handler = "start-ecr-scans.handler"

  environment {
    variables = {
      REPOSITORIES = jsonencode(var.ecr_repositories_to_scan_daily)
      TAGS_TO_SCAN = jsonencode(var.tags_to_scan)
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "start_ecr_scans_lambda_errors" {
  alarm_name = "lambda:${aws_lambda_function.start_ecr_scans.function_name} Errors"
  alarm_description = "Lambda function ${aws_lambda_function.start_ecr_scans.function_name} raised more than one exception in 10 minutes"
  dimensions = {
    FunctionName = aws_lambda_function.start_ecr_scans.function_name
  }
  namespace = "AWS/Lambda"
  metric_name = "Errors"

  # Alert if the function raises an error more than once in a 10-minute period
  # Q: Why more than once? Won't this miss some errors?
  # A: Lambda automatically retries function errors twice. For a given invocation, the function will be
  #    attempted 3 times before it gives up. Alerting on the second exception should catch persistent errors,
  #    while avoiding noise from temporary network glitches.
  statistic = "Sum"
  period = 600
  comparison_operator = "GreaterThanThreshold"
  threshold = 1
  evaluation_periods = 1

  treat_missing_data = "notBreaching"
  alarm_actions = [data.aws_sns_topic.lambda_errors.arn]
  ok_actions = [data.aws_sns_topic.lambda_errors.arn]
  insufficient_data_actions = []
}

resource "aws_cloudwatch_event_rule" "daily_ecr_scans" {
  name = "daily-ecr-scans"
  description = "Once a day, kick off manual scans of images in ECR repositories"

  # Run every day at 12:00 PM, UTC time
  schedule_expression = "cron(0 12 * * ? *)"
}

resource "aws_cloudwatch_event_target" "daily_ecr_scans" {
  target_id = "StartDailyEcrScans"
  arn  = aws_lambda_function.start_ecr_scans.arn
  rule = aws_cloudwatch_event_rule.daily_ecr_scans.id
}

resource "aws_lambda_permission" "allow_event_to_trigger_daily_ecr_scans" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.start_ecr_scans.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_ecr_scans.arn
}
