# output "lb_dns_name" {
#   description = "The DNS name of the load balancer"
#   value       = aws_lb.elb.dns_name
# }

#Output the ALB DNS address to hit your nginx servers. 
output "nginx_alb_dns_name" {
  description = "Public DNS name of the NGINX ALB"
  value       = aws_lb.nginx_alb.dns_name
}

#Configure your app to connect to the primary RDS node
output "db_endpoint" {
  description = "DNS endpoint of the RDS primary instance"
  value       = aws_db_instance.rds.address
}