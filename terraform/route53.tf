# プライベートホストゾーン
resource "aws_route53_zone" "private" {
  name = "local"

  vpc {
    vpc_id = aws_vpc.psql-update-vpc.id
  }

  tags = {
    Name = "psql-update-private-zone"
  }
}

# Aurora Writer エンドポイントへの CNAME レコード
resource "aws_route53_record" "aurora" {
  zone_id = aws_route53_zone.private.zone_id
  name    = "aurora.local"
  type    = "CNAME"
  ttl     = 300

  records = [aws_rds_cluster.aurora-cluster.endpoint]
}