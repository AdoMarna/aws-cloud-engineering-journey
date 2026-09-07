resource "aws_ecr_repository" "app" {
  name                 = "proj05-app-${terraform.workspace}"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "docker_image" "app" {
  name = "${aws_ecr_repository.app.repository_url}:latest"

  build {
    context    = path.root
    dockerfile = "${path.root}/Dockerfile"
  }
}

resource "docker_registry_image" "app" {
  name          = "${aws_ecr_repository.app.repository_url}:latest"
  keep_remotely = true

  triggers = {
    image = docker_image.app.image_id
  }
}

resource "aws_cloudwatch_log_group" "ecs" {
  name = "/ecs/proj05-app-${terraform.workspace}"

  tags = {
    Project     = "proj05"
    Environment = terraform.workspace
  }
}


# alb, target group et listner
resource "aws_lb" "main" {
  name               = "proj05-alb-${terraform.workspace}"
  load_balancer_type = "application"
  security_groups    = [var.sg_alb_id]
  subnets            = [var.public_subnet_az1_id, var.public_subnet_az2_id]

  tags = {
    Project     = "proj05"
    Environment = terraform.workspace
  }
}

resource "aws_lb_target_group" "main" {
  name        = "proj05-tg-${terraform.workspace}"
  protocol    = "HTTP"
  port        = 8080
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    protocol = "HTTP"
    path     = "/health"
    enabled  = true
  }

  tags = {
    Project     = "proj05"
    Environment = terraform.workspace
  }
}

resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }

  tags = {
    Project     = "proj05"
    Environment = terraform.workspace
  }
}

resource "aws_iam_role" "ecs_task_execution" {
  name = "ecsTaskExecutionRole-${terraform.workspace}"

  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "ecs-tasks.amazonaws.com"
        },
        "Action" : "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "role-attach" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# task definition
resource "aws_ecs_task_definition" "app" {
  family = "fargate-task-definition-${terraform.workspace}"

  runtime_platform {
    operating_system_family = "LINUX"
  }

  execution_role_arn = aws_iam_role.ecs_task_execution.arn

  network_mode = "awsvpc"

  requires_compatibilities = ["FARGATE"]

  cpu    = "256"
  memory = "512"

  container_definitions = jsonencode([
    {
      name  = "my-app"
      image = docker_registry_image.app.name

      logConfiguration = {
        logDriver = "awslogs"

        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }

      portMappings = [
        {
          containerPort = 8080
          protocol      = "tcp"
        }
      ]
    }
  ])

  tags = {
    Project     = "proj05"
    Environment = terraform.workspace
  }
}


# cluster et Service
resource "aws_ecs_cluster" "main" {
  name = "proj05-cluster-${terraform.workspace}"

  configuration {
    execute_command_configuration {
      logging = "DEFAULT"
    }
  }

  tags = {
    Project     = "proj05"
    Environment = terraform.workspace
  }
}

resource "aws_ecs_service" "main" {
  name             = "my-ecs-service-${terraform.workspace}"
  cluster          = aws_ecs_cluster.main.id
  task_definition  = aws_ecs_task_definition.app.arn
  desired_count    = 2
  launch_type      = "FARGATE"
  platform_version = "LATEST"

  network_configuration {
    subnets          = [var.private_subnet_az1_id, var.private_subnet_az2_id]
    security_groups  = [var.sg_app_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.main.arn
    container_port   = 8080
    container_name   = "my-app"
  }

  tags = {
    Project     = "proj05"
    Environment = terraform.workspace
  }
}














