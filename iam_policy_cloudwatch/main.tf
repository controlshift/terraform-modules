# role names as string separated by ','
variable "roles" {}

variable "region" { default = "" }

variable "env" {}

variable "app" {}

locals {
  region_prefix = var.region != "" ? "-${var.region}" : ""
}

resource "aws_iam_policy" "manage_cloudwatch" {
  name = "${var.app}${local.region_prefix}-${var.env}-manage-cloudwatch"
  # Currently CloudWatch API doesn't support resource-level permissions (https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/permissions-reference-cw.html)
  #tfsec:ignore:aws-iam-no-policy-wildcards
  policy = <<POLICY
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "Stmt1426849513000",
            "Effect": "Allow",
            "Action": [
                "cloudwatch:PutMetricData",
                "cloudwatch:PutMetricAlarm",
                "cloudwatch:DescribeAlarms",
                "cloudwatch:DeleteAlarms"
            ],
            "Resource": [
                "*"
            ]
        }
    ]
}
POLICY

}

resource "aws_iam_policy_attachment" "manage_cloudwatch" {
  name = "${var.app}${local.region_prefix}-${var.env}-manage-cloudwatch"
  roles = split(",", var.roles)
  policy_arn = aws_iam_policy.manage_cloudwatch.arn
}
