# role names as string separated by ','
variable "roles" {}

variable "region" {}

variable "env" {}

variable "app" {}

resource "aws_iam_policy" "manage_cloudwatch" {
  name = "${var.app}-${var.region}-${var.env}-manage-cloudwatch"
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
  name = "${var.app}-${var.region}-${var.env}-manage-cloudwatch"
  roles = split(",", var.roles)
  policy_arn = aws_iam_policy.manage_cloudwatch.arn
}
