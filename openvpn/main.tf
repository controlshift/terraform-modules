#--------------------------------------------------------------
# This module creates all resources necessary for OpenVPN
#
# Adapted from Terraform best practices:
# https://raw.githubusercontent.com/hashicorp/best-practices/master/terraform/modules/aws/network/openvpn/openvpn.tf
#--------------------------------------------------------------

variable "name"               { default = "openvpn" }
variable "vpc_id"             { }
variable "vpc_cidr"           { }
variable "public_subnet_ids"  { }
variable "ssl_cert"           { }
variable "ssl_key"            { }
variable "ssh_username"       { }
variable "ami"                { default = "ami-5fe36434" }
variable "instance_type"      { }
variable "openvpn_user"       { }
variable "openvpn_admin_user" { }
variable "openvpn_admin_pw"   { }
variable "vpn_cidr"           { }
variable "route_zone_id"      { }
variable "route_zone_name"    { }
variable "app_environment"    { }
variable "ssh_cidr_block"     { }
variable "public_hosted_zone_id" {}

resource "aws_security_group" "openvpn" {
  name   = "${var.name}"
  vpc_id = "${var.vpc_id}"
  description = "OpenVPN security group"

  tags { Name = "${var.name}" }

  ingress {
    protocol    = -1
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["${var.vpc_cidr}"]
  }

  # For OpenVPN Client Web Server & Admin Web UI
  ingress {
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = ["0.0.0.0/0"]
  }

  # For SSH
  ingress {
    protocol    = "tcp"
    from_port   = 22
    to_port     = 22
    cidr_blocks = ["${var.ssh_cidr_block}"]
  }

  ingress {
    protocol    = "udp"
    from_port   = 1194
    to_port     = 1194
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol    = -1
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "openvpn" {
  ami           = "${var.ami}"
  instance_type = "${var.instance_type}"
  subnet_id     = "${element(split(",", var.public_subnet_ids), count.index)}"
  associate_public_ip_address = true
  vpc_security_group_ids = ["${aws_security_group.openvpn.id}"]
  iam_instance_profile = "${aws_iam_instance_profile.vpn.name}"

  tags {
    Name = "${var.name}"
    environment = "${var.app_environment}"
    kind = "vpn"
  }

  # `admin_user` and `admin_pw` need to be passed in to the appliance through `user_data`, see docs -->
  # https://docs.openvpn.net/how-to-tutorialsguides/virtual-platforms/amazon-ec2-appliance-ami-quick-start-guide/
  user_data = <<USERDATA
admin_user=${var.openvpn_admin_user}
admin_pw=${var.openvpn_admin_pw}
USERDATA

  provisioner "remote-exec" {
    connection {
      user         = "${var.ssh_username}"
      host         = "${aws_instance.openvpn.public_ip}"
    }

    inline = [
      # sleep for 20 seconds to wait for openvpn startup
      "sleep 15",
      "sudo ovpn-init --ec2 --batch --force",
      # wait for network to come back up
      "sleep 15",
      # Insert our SSL cert
      "echo '${var.ssl_cert}' | sudo tee /usr/local/openvpn_as/etc/web-ssl/server.crt > /dev/null",
      "echo '${var.ssl_key}' | sudo tee /usr/local/openvpn_as/etc/web-ssl/server.key > /dev/null",
      # Set VPN network info
      "sudo /usr/local/openvpn_as/scripts/sacli -k vpn.daemon.0.client.network -v ${element(split("/", var.vpn_cidr), 0)} ConfigPut",
      "sudo /usr/local/openvpn_as/scripts/sacli -k vpn.daemon.0.client.netmask_bits -v ${element(split("/", var.vpn_cidr), 1)} ConfigPut",
      # Do a warm restart so the config is picked up
      "sudo /usr/local/openvpn_as/scripts/sacli start",
    ]
  }
  provisioner "local-exec" {
    command = "ruby provision setup_vpn_dns --environment=${var.app_environment} --aws_vpn_name=${aws_instance.openvpn.public_dns}"
  }
}


resource "aws_iam_role" "vpn" {
  name = "vpn-${var.app_environment}"
  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole",
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
POLICY
}

resource "aws_iam_instance_profile" "vpn" {
  name = "vpn-${var.app_environment}"
  roles = ["${aws_iam_role.vpn.name}"]
}

module "iam_describe_ec2" {
  source = "github.com/controlshift/terraform-modules//iam_policy_describe_ec2"
  roles = "${aws_iam_role.vpn.name}"
  env = "${var.app_environment}"
  app = "vpn"
}

module "iam_manage_cloudwatch" {
  source = "github.com/controlshift/terraform-modules//iam_policy_cloudwatch"
  roles = "${aws_iam_role.vpn.name}"
  env = "${var.app_environment}"
  app = "vpn"
}

resource "aws_iam_policy" "vpn_domain" {
  name = "vpn-domain-management-${var.app_environment}"
  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "route53:ChangeResourceRecordSets",
        "route53:ListResourceRecordSets"
      ],
      "Resource": [
        "arn:aws:route53:::hostedzone/${var.route_zone_id}",
        "arn:aws:route53:::hostedzone/${var.public_hosted_zone_id}"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "route53:ListHostedZonesByName"
      ],
      "Resource": [
        "*"
      ]
    }
  ]
}
POLICY
}

resource "aws_iam_policy_attachment" "vpn_domains_for_hostnames" {
  name = "vpn-${var.app_environment}-manage-domains-for-hostnames"
  roles = ["${aws_iam_role.vpn.name}"]
  policy_arn = "${aws_iam_policy.vpn_domain.arn}"
}

resource "aws_route53_record" "openvpn" {
  zone_id = "${var.route_zone_id}"
  name    = "app.${var.route_zone_name}"
  type    = "A"
  ttl     = "300"
  records = ["${aws_instance.openvpn.public_ip}"]
}

output "private_ip"  { value = "${aws_instance.openvpn.private_ip}" }
output "public_ip"   { value = "${aws_instance.openvpn.public_ip}" }
output "public_fqdn" { value = "${aws_route53_record.openvpn.fqdn}" }