# role name
variable "roles" {}
variable "env" {}
variable "app" {}

resource "aws_iam_policy" "describe_ec2" {
  name = "${var.app}-${var.env}-describe-ec2"
  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:Describe*"
      ],
      "Resource": [
        "*"
      ]
    }
  ]
}
POLICY
}

resource "aws_iam_policy_attachment" "describe_ec2" {
  name = "${var.app}-${var.env}-describe-ec2"
  roles = "${split(",", var.roles)}"
  policy_arn = "${aws_iam_policy.describe_ec2.arn}"
}
