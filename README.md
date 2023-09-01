# terraform-modules
Some terraform modules

* `cloudwatch_elb`: Cloudwatch alarms for an ELB
* `cloudwatch_alb_target_group`: Cloudwatch alarms for a target group behind an Application Load Balancer
* `iam_policy_describe_ec2`: An IAM policy allowing roles to describe things in EC2
* `iam_policy_cloudwatch`: An IAM policy allowing roles to manage CloudWatch alarms and send data to CloudWatch
* `ecr_scanning`: A set of Lambda functions that help with vulnerability scans on docker images in ECR. The `ecrScanResultsToSlack` Lambda function reports vulnerability findins to Slack, `startEcrScans` is executed daily to trigger scans on images with specific tags.
