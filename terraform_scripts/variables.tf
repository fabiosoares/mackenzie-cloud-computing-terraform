variable "aws_region" {
  description = "Região da AWS onde os recursos serão provisionados"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Nome do projeto para tags"
  type        = string
  default     = "HAWebApp"
}

variable "vpc_cidr" {
  description = "Bloco CIDR para a VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnets_cidr" {
  description = "Lista de blocos CIDR para as sub-redes públicas"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnets_cidr" {
  description = "Lista de blocos CIDR para as sub-redes privadas"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "instance_type" {
  description = "Tipo de instância EC2"
  type        = string
  default     = "t2.micro"
}

variable "ami_id" {
  description = "ID da AMI para as instâncias EC2 (deve ser uma AMI compatível com a região)"
  type        = string
  default     = "ami-053b0d534c3757829" # AMI do Amazon Linux 2 na us-east-1
}

variable "key_name" {
  description = "Nome do par de chaves SSH para as instâncias EC2"
  type        = string
  default     = "my-key-pair"
}

variable "domain_name" {
  description = "Nome do domínio para o registro Route 53 (opcional)"
  type        = string
  default     = "exemplo.com"
}
