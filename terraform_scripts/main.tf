# 1. VPC e Redes
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-VPC"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-IGW"
  }
}

# Sub-redes Públicas
resource "aws_subnet" "public" {
  count             = length(var.public_subnets_cidr)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnets_cidr[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-Public-Subnet-${count.index + 1}"
  }
}

# Tabela de Rotas Pública
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "${var.project_name}-Public-RT"
  }
}

# Associações da Tabela de Rotas Pública
resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Sub-redes Privadas (para ELB e Auto Scaling)
resource "aws_subnet" "private" {
  count             = length(var.private_subnets_cidr)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnets_cidr[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.project_name}-Private-Subnet-${count.index + 1}"
  }
}

# Data Source para Zonas de Disponibilidade
data "aws_availability_zones" "available" {
  state = "available"
}

# 2. Security Group (Grupo de Segurança)
resource "aws_security_group" "web_sg" {
  name        = "${var.project_name}-Web-SG"
  description = "Allow HTTP HTTPS and SSH traffic"
  vpc_id      = aws_vpc.main.id

  # Regra de entrada para HTTP (porta 80)
  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Regra de entrada para HTTPS (porta 443)
  ingress {
    description = "HTTPS de qualquer lugar"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Regra de entrada para SSH (porta 22) - Apenas para fins de gerenciamento
  ingress {
    description = "SSH de qualquer lugar"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Idealmente, restrinja isso ao seu IP
  }

  # Regra de saída
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-Web-SG"
  }
}

# 3. Elastic Load Balancing (Application Load Balancer)
resource "aws_lb" "web_alb" {
  name               = "${var.project_name}-ALB"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = aws_subnet.public[*].id # O ALB deve estar nas sub-redes públicas

  enable_deletion_protection = false

  tags = {
    Name = "${var.project_name}-ALB"
  }
}

# Grupo de Destino (Target Group)
resource "aws_lb_target_group" "web_tg" {
  name     = "${var.project_name}-TG"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "${var.project_name}-TG"
  }
}

# Listener do ALB (porta 80)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.web_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_tg.arn
  }
}

# 4. Auto Scaling
# Configuração de Lançamento (Launch Template)
resource "aws_launch_template" "web_lt" {
  name_prefix   = "${var.project_name}-LT"
  image_id      = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name

  network_interfaces {
    associate_public_ip_address = false # Instâncias EC2 em sub-redes privadas não precisam de IP público
    security_groups             = [aws_security_group.web_sg.id]
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    # Instala o servidor web Apache e uma página de teste
    yum update -y
    yum install -y httpd
    systemctl start httpd
    systemctl enable httpd
    echo "<h1>Aplicação Web Altamente Disponível - Zona $(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)</h1>" > /var/www/html/index.html
    EOF
  )

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "${var.project_name}-EC2-Instance"
    }
  }
}

# Grupo de Auto Scaling (Auto Scaling Group)
resource "aws_autoscaling_group" "web_asg" {
  name                      = "${var.project_name}-ASG"
  vpc_zone_identifier       = aws_subnet.private[*].id # O ASG deve usar as sub-redes privadas
  target_group_arns         = [aws_lb_target_group.web_tg.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 300

  desired_capacity = 2
  max_size         = 4
  min_size         = 2

  launch_template {
    id      = aws_launch_template.web_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-ASG-Instance"
    propagate_at_launch = true
  }
}

# Política de Escalonamento (Scaling Policy) - Exemplo de CPU
resource "aws_autoscaling_policy" "cpu_scale_up" {
  name                   = "${var.project_name}-ScaleUp-Policy"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.web_asg.name
}

resource "aws_autoscaling_policy" "cpu_scale_down" {
  name                   = "${var.project_name}-ScaleDown-Policy"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.web_asg.name
}

# Alarme do CloudWatch para Escalonamento (CPU > 80%)
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.project_name}-CPU-High-Alarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Increase capacity if CPU utilization is > 80% for 2 minutes"
  
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web_asg.name
  }

  alarm_actions = [aws_autoscaling_policy.cpu_scale_up.arn]
}

# Alarme do CloudWatch para Escalonamento (CPU < 30%)
resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "${var.project_name}-CPU-Low-Alarm"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 30
  alarm_description   = "Decrease capacity if CPU utilization is < 30% for 2 minutes"
  
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web_asg.name
  }

  alarm_actions = [aws_autoscaling_policy.cpu_scale_down.arn]
}

# 5. Route 53 (Opcional, requer um Hosted Zone existente)
# Este bloco é um placeholder. Para que funcione, você deve ter um Hosted Zone
# existente na sua conta AWS com o nome de domínio especificado.
/*
resource "aws_route53_record" "web_app" {
  zone_id = data.aws_route53_zone.selected.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.web_alb.dns_name
    zone_id                = aws_lb.web_alb.zone_id
    evaluate_target_health = true
  }
}

data "aws_route53_zone" "selected" {
  name         = "${var.domain_name}."
  private_zone = false
}
*/

# Saídas (Outputs)
output "alb_dns_name" {
  description = "Nome DNS do Application Load Balancer"
  value       = aws_lb.web_alb.dns_name
}

output "public_subnets" {
  description = "IDs of public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnets" {
  description = "IDs das sub-redes privadas"
  value       = aws_subnet.private[*].id
}
