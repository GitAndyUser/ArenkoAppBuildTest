resource "aws_lb" "nginx_alb" {
  name               = "nginx-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = [aws_subnet.public-1.id, aws_subnet.public-2.id]
  security_groups    = [aws_security_group.ecs-sgrp.id]

  enable_deletion_protection = false

  enable_http2                     = true
  enable_cross_zone_load_balancing = true

  tags = {
    Name = "${var.env}-alb"
  }
}

resource "aws_lb_listener" "nginx_listener" {
  load_balancer_arn = aws_lb.nginx_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nginx_target_group.arn
  }
}

resource "aws_lb_target_group" "nginx_target_group" {
  name     = "nginx-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc.id

  health_check {
    path = "/"
  }

}

resource "aws_lb_target_group_attachment" "nginx_target_group_attachment" {
  target_group_arn = aws_lb_target_group.nginx_target_group.arn
  target_id        = aws_ecs_service.nginx_service.name

}
