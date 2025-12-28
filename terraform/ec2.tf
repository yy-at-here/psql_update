# IAM Role for EC2
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2-role" {
  name               = "psql-update-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

# SSM Session Manager用のマネージドポリシーをアタッチ
resource "aws_iam_role_policy_attachment" "bastion-ssm" {
  role       = aws_iam_role.ec2-role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "bastion" {
  name = "psql-update-bastion-profile"
  role = aws_iam_role.ec2-role.name
}

resource "aws_instance" "bastion" {
  ami                    = "ami-09cd9fdbf26acc6b4"
  instance_type          = "t3.medium"
  subnet_id              = aws_subnet.private-subnet-bastion-a.id
  vpc_security_group_ids = [aws_security_group.bastion-sg.id]
  iam_instance_profile   = aws_iam_instance_profile.bastion.name
  user_data              = file("./user_data.sh")

  tags = {
    Name = "psql-update-bastion"
  }
}


# security group
resource "aws_security_group" "bastion-sg" {
  name        = "psql-update-only-outbound"
  description = "security group for bastion host"
  vpc_id      = aws_vpc.psql-update-vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

output "ec2_instance_id" {
  value = aws_instance.bastion.id
}
