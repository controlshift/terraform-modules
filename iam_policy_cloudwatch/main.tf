# role name
variable "role" {}

resource "aws_iam_policy" "manage_cloudwatch" {
  name = "${var.role}-manage-cloudwatch"
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
  name = "${var.role}-manage-cloudwatch"
  roles = ["${var.role}"]
  policy_arn = "${aws_iam_policy.manage_cloudwatch.arn}"
}
