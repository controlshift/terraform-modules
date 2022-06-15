# role names as string separated by ','
variable "roles" {}

variable "region" { default = "" }

variable "env" {}

variable "app" {}

locals {
  region_prefix = var.region != "" ? "-${var.region}" : ""
}

resource "aws_iam_policy" "describe_ec2" {
  name = "${var.app}${local.region_prefix}-${var.env}-describe-ec2"
  # Currently EC2 Describe* and Autoscaling DescribeAutoScaling* APIs don't support resource-level permissions
  # (see https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/iam-policy-structure.html#UsingWithEC2_Actions and
  # https://docs.aws.amazon.com/autoscaling/ec2/userguide/control-access-using-iam.html#policy-auto-scaling-resources)
  #tfsec:ignore:aws-iam-no-policy-wildcards
  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:Describe*",
        "autoscaling:DescribeAutoScalingInstances",
        "autoscaling:DescribeAutoScalingGroups"
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
  name = "${var.app}${local.region_prefix}-${var.env}-describe-ec2"
  roles = split(",", var.roles)
  policy_arn = aws_iam_policy.describe_ec2.arn
}
