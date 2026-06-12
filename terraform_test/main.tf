# SOPS To enable secure user/pass the variables should be added to the secrets.yaml file and then SOPS -e 
# This assumes the operator has installed sops and they have a KMS key arn they can reference. 
# Then encrypt the files sops --encrypt --kms arn:aws:kms:eu-west-1:accountID:key/blah-blah-blah-blah secrets.yaml > secrets.enc.yaml
# Operator need to be careful that the origional unencrypted file is not checked into bitbucket like I have done here to allow you to see the format. 
# Only operators with access to the AWS kms key will be able to extract and read this secrets.enc.yaml
# Other probably better fit solutions are availiable. If you have Directory Service, aws_secretsmanager_secret_version. 


locals{
  vars_encryted = yamldecode(sops_decrypt_file(find_in_parent_folders("secrets.enc.yaml")))
}

# Create VPC with /16 65k IPs, fine for simple nginx-app-db application
resource "aws_vpc" "vpc" {
  cidr_block           = "10.0.0.0/16"
#seems fine for application senario (not required, but no harm in it)
  instance_tenancy     = "default"
#agree, see no problem
  enable_dns_support   = true
  enable_dns_hostnames = true

}


#agree, see no problem
resource "aws_ecs_cluster" "nginx_cluster" {
  name = "${var.environment}-cluster"
}

resource "aws_ecs_task_definition" "nginx_task" {
# agree
  family                   = "nginx-task"
  network_mode             = "awsvpc"
#Agree, it's not EC2
  requires_compatibilities = ["FARGATE"]
#very small minimum spec
  cpu           = "256"
  memory        = "512"

  task_role_arn = aws_iam_role.ecs_task_role.arn
# Incorrect reference made ecs_execution --> ecs_execution_role as defined later
  execution_role_arn = aws_iam_role.ecs_execution_role.arn

# no comments inside JSON  
# Don't think Comma should be at the end of the portmappings 

  container_definitions = jsonencode([{
    name  = "nginx-container"
    image = "nginx:latest"

    portMappings = [{
      containerPort = 80
      hostPort      = 80
    }
    ]
  }])
}

#No application layer ECS task or definition. 
#set port to 8080 for app servers listener
resource "aws_ecs_task_definition" "app_task" {
  family                   = "app-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"

  task_role_arn      = aws_iam_role.ecs_task_role.arn
  execution_role_arn = aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([
    {
      name  = "app-container"
      image = var.app_image   

      portMappings = [{
        containerPort = 8080
        hostPort      = 8080
      }]
    }
  ])
}




# using these roles, but there are no role definitions attached to the roles 
resource "aws_iam_role" "ecs_task_role" {
  name = "ecs-task-role"

# More commas on lines?
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
}

#re-visit depending on if nginx requires any inputs or variables to read. 

resource "aws_iam_role_policy_attachment" "ecs_task_role_ssm" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess"
}

resource "aws_iam_role" "ecs_execution_role" {
  name = "ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
}

# No policy is attached to the roles
resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_ecs_service" "nginx_service" {
  name            = "${var.environment}-${var.service}"
  cluster         = aws_ecs_cluster.nginx_cluster.id
  task_definition = aws_ecs_task_definition.nginx_task.arn
  launch_type     = "FARGATE"
#this is not required, but maybe to consider with HA for reliability and help prevent restart downtime while ALB re-sets Set to 2 for 1 in each AZ. HA using LB is not perfect and will still experience upto 60 seconds of 404 if an nginx fails.
# Added as a variable to demonstrate possible configurations which could vary and more easyily changed or defined as a variable
  desired_count = ${var.desired_num_nginx} 

# Wrong app netowrk and should be in the ALB public subnet
# I actually left the , in this time because it is a list and makes the code block smaller and more readable I think. 
  network_configuration {
    subnets         = [aws_subnet.public_1.id, aws_subnet.public_2.id]
    security_groups = [aws_security_group.ecs_sgrp.id]
  }

#But there is no loadbalancer created to add this service? The ALB will target Nginx and Nginx will need to be configured to proxy pass to the app_target_group.arn
  load_balancer {
    target_group_arn = aws_lb_target_group.nginx_target_group.arn
    container_name   = "nginx-container"
# Looks like typo based on earlier port mappings 81 --> 80
    container_port   = 80
  }
# Yes important to prevent race delete of arn before instance
  depends_on = [aws_ecs_task_definition.nginx_task]
}

#new  task to create ECS application servers 
#THis should be set to desired 2 for HA and LB across 2 AZ but left. LB HA is not perfect and will take upto 60s + to detect an app failure and re-route traffic 500 errors likely. How long does a new app take to spin up? size of jboss jvm etc?

resource "aws_ecs_service" "app_service" {
  name            = "${var.environment}-app"
  cluster         = aws_ecs_cluster.nginx_cluster.id
  task_definition = aws_ecs_task_definition.app_task.arn
  launch_type     = "FARGATE"
  desired_count   = ${var.desired_num_app}  

  network_configuration {
    subnets         = [aws_subnet.web_1.id, aws_subnet.web_2.id]
    security_groups = [aws_security_group.application_sgrp.id]
  }

  load_balancer {
  target_group_arn = aws_lb_target_group.app_tg.arn
  container_name   = "app-container"
  container_port   = 8080
}

  depends_on = [
    aws_lb_listener.app_listener, aws_ecs_task_definition.app_task
  ]
}

############## subnet creation ##################
#Hypens I dislike and I think a bad convention in terraform function names and can cause problems in terraform, especially if executed through windows powershell. 
#later finding this has been applied inconsistently so corrected. 

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.0.0/24"
  availability_zone       = "eu-west-2a"
  map_public_ip_on_launch = true

}
# no you cannot share a subnet across AZs set from "10.0.0.0/24" to "10.0.1.0/24"
resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "eu-west-2b"
  map_public_ip_on_launch = true
}



resource "aws_subnet" "web_1" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.2.0/16"
  availability_zone       = "eu-west-2a"
  map_public_ip_on_launch = false

}
#Fix the subnet as used in DB "10.0.6.0/24" --> "10.0.3.0/24"
resource "aws_subnet" "web_2" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = "eu-west-2b"
  map_public_ip_on_launch = false

}

resource "aws_subnet" "database_1" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.5.0/24"
  availability_zone       = "eu-west-2a"
  map_public_ip_on_launch = false

}

resource "aws_subnet" "database_2" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.6.0/24"
  availability_zone       = "eu-west-2b"
  map_public_ip_on_launch = false

}

#wrong cidr block error "0.0.0.0" --> "0.0.0.0/0"
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

}

######################################

resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "rt_aza" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_az_a.id
  }
}

#Need this to route AZ_b traffic to internet from private. See note below on creating 2 EIP NAT gateway for each AZ
resource "aws_route_table" "rt_azb" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_az_b.id
  }
}

# do these server need access to the internet? 
resource "aws_route_table_association" "web_aza" {
  subnet_id      = aws_subnet.web_1.id
  route_table_id = aws_route_table.rt_aza.id
}

# attaching to wrong table aza --> azb
resource "aws_route_table_association" "web_azb" {
  subnet_id      = aws_subnet.web_2.id
  route_table_id = aws_route_table.rt_azb.id
}

################ Security groups ###################
#adding the new ALB security group for the Nginx ALB 

resource "aws_security_group" "alb_sg" {
  name        = "${var.environment}-public-alb-sg"
  description = "Public ALB security group"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description = "Allow HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description     = "Allow ALB to reach NGINX ECS tasks"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_sg.id]
  }
}

#adding ALB security group for the App ALB
resource "aws_security_group" "app_alb_sg" {
  name        = "${var.environment}-app-alb-sg"
  description = "Internal ALB for App layer"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description     = "Allow Nginx to reach App ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_sgrp.id]
  }

  egress {
    description     = "Allow ALB to reach App ECS tasks"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.application_sgrp.id]
  }
}


# Description wrong, not inbound, Perhaps suggest traffic is only allowed access to web network and not onto internet. 
# Bring togehter security groups to read more easily
#I'll let the outbound to all ports stay as AWS recommends but I think this could be set to least permissive. 
#re-written to account for a new application LB
resource "aws_security_group" "ecs_sgrp" {
  name        = "sgrp-web-server"
  description = "Nginx ECS tasks"
  vpc_id      = aws_vpc.vpc.id

   ingress {
    description     = "Allow ALB to reach Nginx"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    description     = "Allow NGinx to reach App ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.app_alb_sg.id]
  }
}


resource "aws_security_group" "application_sgrp" {
  name        = "sgrp-application"
  description = "Allow inbound from ALB, outbound to DB"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description     = "Allow HTTP from Internal ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.app_alb_sg.id]
  }

  egress {
    description = "Allow outbound to DB"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [aws_security_group.database_sgrp.id]
  }
}


# More hypens
#dangerous as this will expose database to be accessed by all internet. 0.0.0.0/0
# restrict incoming from application_grp only 
#remove all outbound for the DB but keep an egress rule present
resource "aws_security_group" "database_sgrp" {
  name        = "sgrp-database"
  description = "Allow inbound traffic from application security group"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description = "Allow traffic from application layer"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [aws_security_group.application_sgrp.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
##############################################

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

}

# more hyphens in use
resource "aws_nat_gateway" "nat_az_a" {
  subnet_id     = aws_subnet.public_1.id
  allocation_id = aws_eip.nat_a.id

  depends_on = [
    aws_subnet.public_1
  ]
}

resource "aws_eip" "nat_a" {
  vpc = aws_vpc.vpc.id

}
# Why no second AZ_b NAT, depending on outgoing calls would save money on inter AZ data costs. 
# Although this would need discussing as it each EIP incurrs a cost. depends on the nature of the traffic and what is being used. 

resource "aws_nat_gateway" "nat_az_b" {
  subnet_id     = aws_subnet.public_2.id
  allocation_id = aws_eip.nat_b.id

  depends_on = [
    aws_subnet.public_2
  ]
}

resource "aws_eip" "nat_b" {
  vpc = aws_vpc.vpc.id
}


#set to join wrong subnet for public_1,2 --> set to database_1,2
#I cannot see how this will work. Unless the DB's are read only. 
#The database would require syncing across AZs Which is hard to accomplish unless a daily or however frequent DMS (Data Migration Service) is setup. 
# there is no HA load balancing between the D
resource "aws_db_instance" "rds" {
  allocated_storage      = 10
  db_subnet_group_name   = aws_db_subnet_group.subnet_group.id
  engine                 = "postgres"
  engine_version         = "postgres13"
  instance_class         = "db.t2.micro"
  #instance type is very small for a multiAZ public facing web app? 1cpu, 1gb ram, depends on profile of work requested, execution plans, uniqueness of queries or it RO or RW etc
  multi_az               = true
  name                   = "mydb"
  username               = local.vars_encryted.DBusername
  password               = local.vars_encryted.DBpassword
  skip_final_snapshot    = true
  vpc_security_group_ids = [aws_security_group.database_sgrp.id]
}

resource "aws_db_subnet_group" "subnet_group" {
  name       = "main"
  subnet_ids = [aws_subnet.database_1.id, aws_subnet.database_2.id]

}
