provider "aws" {
  region = "us-east-1"
}

data "aws_region" "current" {}

variable "ssh_public_key" {
  type = string
}

variable "sentry_backend_dsn" {
  type    = string
  default = ""
}

variable "sentry_frontend_dsn" {
  type    = string
  default = ""
}

variable "domain_name" {
  type = string
}

variable "worker_ami_id" {
  type = string
}

resource "aws_default_vpc" "default" {
  tags = {
    Name = "Default VPC"
  }
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [aws_default_vpc.default.id]
  }
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_service_discovery_http_namespace" "internal" {
  name = "internal"
}

resource "aws_cloudwatch_log_group" "histomics_logs" {
  name = "histomics-logs"
}

resource "aws_security_group" "lb_sg" {
  name   = "lb-sg"
  vpc_id = aws_default_vpc.default.id

  ingress {
    description      = "Open 80 to the internet"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description      = "Open 443 to the internet"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_security_group" "histomics_sg" {
  name = "histomics-sg"

  vpc_id = aws_default_vpc.default.id

  ingress {
    description = "Allow members of this security group to talk to port 27017"
    from_port   = 27017
    to_port     = 27017
    protocol    = "tcp"
    self        = true
  }

  ingress {
    description     = "Allow load balancer SG to talk to port 8080"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.lb_sg.id]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_lb" "ecs_lb" {
  name               = "ecs-lb"
  internal           = false
  load_balancer_type = "application"
  subnets            = data.aws_subnets.default.ids
  security_groups    = [aws_security_group.lb_sg.id]
}

resource "aws_lb_target_group" "ecs_target_group" {
  name        = "ecs-target-group"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_default_vpc.default.id
  target_type = "ip"

  health_check {
    path = "/"
  }
}

resource "aws_lb_listener" "ecs_lb_listener_http" {
  load_balancer_arn = aws_lb.ecs_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_acm_certificate" "front_cert" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_zone" "primary" {
  name = var.domain_name
}

resource "aws_route53_record" "cert_validation" {
  name    = tolist(aws_acm_certificate.front_cert.domain_validation_options).0.resource_record_name
  type    = tolist(aws_acm_certificate.front_cert.domain_validation_options).0.resource_record_type
  zone_id = aws_route53_zone.primary.zone_id
  records = [tolist(aws_acm_certificate.front_cert.domain_validation_options).0.resource_record_value]
  ttl     = 60
}

resource "aws_route53_record" "front_lb" {
  name    = var.domain_name
  type    = "A"
  zone_id = aws_route53_zone.primary.zone_id

  alias {
    name                   = aws_lb.ecs_lb.dns_name
    zone_id                = aws_lb.ecs_lb.zone_id
    evaluate_target_health = true
  }
}

resource "aws_acm_certificate_validation" "front_cert_validation" {
  certificate_arn         = aws_acm_certificate.front_cert.arn
  validation_record_fqdns = [aws_route53_record.cert_validation.fqdn]
}

resource "aws_lb_listener" "ecs_lb_listener_https" {
  load_balancer_arn = aws_lb.ecs_lb.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = aws_acm_certificate.front_cert.arn

  default_action {
    target_group_arn = aws_lb_target_group.ecs_target_group.arn
    type             = "forward"
  }
}

resource "aws_ecs_cluster" "histomics_cluster" {
  name = "histomics"
}

resource "aws_ecs_task_definition" "histomics_task" {
  family                   = "histomics-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 4096
  memory                   = 16384
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  container_definitions = jsonencode(
    [
      {
        name  = "histomics-server"
        image = "zachmullen/histomics-load-test@sha256:37bec4bbeac4dfa30e816a27eb1594f66f2b45e5731ef8ede3877f29dd4ddf0d"
        entryPoint = [
          "gunicorn",
          "girder.wsgi:app",
          "--bind=0.0.0.0:8080",
          "--workers=4",
          "--preload",
          "--timeout=30"
        ],
        cpu       = 4096
        memory    = 16384
        essential = true
        healthCheck = {
          command     = ["CMD-SHELL", "curl -f http://localhost:8080/ || exit 1"]
          interval    = 30
          timeout     = 5
          retries     = 3
          startPeriod = 30
        }
        portMappings = [
          {
            containerPort = 8080
            hostPort      = 8080
          }
        ]
        environment = [
          {
            name  = "GIRDER_MONGO_URI"
            value = local.mongodb_connection_string
          },
          {
            name  = "GIRDER_WORKER_BROKER"
            value = "amqps://histomics:${random_password.mq_password.result}@${aws_mq_broker.jobs_queue.id}.mq.${data.aws_region.current.region}.on.aws:5671"
          },
          {
            name  = "SENTRY_BACKEND_DSN"
            value = var.sentry_backend_dsn
          },
          {
            name  = "SENTRY_FRONTEND_DSN"
            value = var.sentry_frontend_dsn
          },
          {
            name  = "GIRDER_MAX_CURSOR_TIMEOUT_MS"
            value = "3600000" # DocumentDB does not support no_timeout cursors
          },
          {
            name  = "GIRDER_STATIC_REST_ONLY" # don't dynamically generate slicer_cli_web endpoints
            value = "true"
          },
          {
            name  = "GIRDER_NOTIFICATION_REDIS_URL"
            value = "redis://default:${random_password.redis_password.result}@${aws_elasticache_replication_group.redis.primary_endpoint_address}:6379"
          },
        ],
        mountPoints = [
          {
            sourceVolume  = "assetstore"
            containerPath = "/assetstore"
            readOnly      = false
          }
        ]
        logConfiguration = {
          logDriver = "awslogs"
          options = {
            awslogs-group         = aws_cloudwatch_log_group.histomics_logs.id
            awslogs-region        = "us-east-1"
            awslogs-stream-prefix = "ecs"
          }
        }
      }
    ]
  )

  volume {
    name = "assetstore"

    efs_volume_configuration {
      file_system_id = aws_efs_file_system.assetstore.id
    }
  }
}

resource "aws_ecs_service" "histomics_service" {
  name            = "histomics-service"
  cluster         = aws_ecs_cluster.histomics_cluster.id
  task_definition = aws_ecs_task_definition.histomics_task.arn
  desired_count   = 2
  depends_on      = [aws_ecs_task_definition.histomics_task]
  launch_type     = "FARGATE"

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.internal.arn
  }

  network_configuration {
    assign_public_ip = true # this should probably be false and we should add a NAT instead
    security_groups  = [aws_security_group.histomics_sg.id]
    subnets          = data.aws_subnets.default.ids
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.ecs_target_group.arn
    container_name   = "histomics-server"
    container_port   = 8080
  }
}
