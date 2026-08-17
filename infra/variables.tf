variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "db_username" {
  description = "Master username for PostgreSQL"
  type        = string
  default     = "pgadmin"
}

/* db_password is generated via random_password resource – no default needed */
variable "db_password" {
  description = "Master password for PostgreSQL (generated automatically)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "db_name" {
  description = "Initial database name"
  type        = string
  default     = "datalake"
}

variable "lambda_timeout" {
  description = "Timeout (seconds) for Lambda functions"
  type        = number
  default     = 30
}
