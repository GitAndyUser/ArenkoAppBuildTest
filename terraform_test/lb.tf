#added an ALB to the front end fargate, this ensure SSL termination, (but archs might want internal private SSL between web and DB)
#Also gains integration with AWS services and is AWS recommanded placement for this architechture 

resource "aws_lb" "nginx_alb" {
  name               = "${var.environment}-nginx-alb"
  load_balancer_type = "application"
  internal           = false

  subnets = [
    aws_subnet.public_1.id, aws_subnet.public_2.id
  ]

  security_groups = [
    aws_security_group.alb_sg.id
  ]
} 

#ALB listening on port 80
resource "aws_lb_listener" "nginx_listener" {
  load_balancer_arn = aws_lb.nginx_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nginx_target_group.arn
  }
}

#target group for the ALB
resource "aws_lb_target_group" "nginx_target_group" {
  name        = "${var.environment}-nginx-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.vpc.id
  target_type = "ip"

  health_check {
    path = "/"
  }
}

/*
Remove the aws_lb_target_group_attachment as this does not apply to fargate ecs and is applied via the lodbalancer block in the instance creation. 
resource "aws_lb_target_group_attachment" "nginx_target_group_attachment" {
  target_group_arn = aws_lb_target_group.nginx_target_group.arn
  target_id        = aws_ecs_service.nginx_service.name

}
*/


#Internal App layer LB configs 
resource "aws_lb" "app_alb" {
  name               = "${var.environment}-app-alb"
  load_balancer_type = "application"
  internal           = true

  subnets = [
    aws_subnet.web_1.id, aws_subnet.web_2.id
  ]

  security_groups = [
    aws_security_group.app_alb_sg.id
  ]
}



resource "aws_lb_listener" "app_listener" {
  load_balancer_arn = aws_lb.app_alb.arn
  port              = 8080
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

resource "aws_lb_target_group" "app_tg" {
  name        = "${var.environment}-app-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.vpc.id
  target_type = "ip"

  health_check {
    path = "/health"
  }
}