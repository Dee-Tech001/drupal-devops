output "alb_dns_name" {
  value = aws_lb.drupal_alb.dns_name
}

output "drupal_server_1_ip" {
  value = aws_instance.drupal_server_1.public_ip
}

output "drupal_server_2_ip" {
  value = aws_instance.drupal_server_2.public_ip
}

output "rds_endpoint" {
  value = aws_db_instance.drupal_db.endpoint
}
