
# ─────────────────────────────────────────────────────────────────────────────
# Remote backend — state stored in S3, locking via DynamoDB
# (Provisioned by the bootstrap/ folder)
# ─────────────────────────────────────────────────────────────────────────────
terraform {
  backend "s3" {
    bucket         = "tfstate-e-commerce-pipeline-a5yogjnu"
    key            = "infra/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "tflock-e-commerce-pipeline-a5yogjnu"
    encrypt        = true
  }
}

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

/* -------------------------------------------------------------------------- */
/* Random suffix for naming resources                                          */
/* -------------------------------------------------------------------------- */
resource "random_string" "suffix" {
  length  = 16
  lower   = true
  upper   = false
  numeric = true
  special = false
}

/* -------------------------------------------------------------------------- */
/* Default VPC & Subnets (network foundation)                                 */
/* -------------------------------------------------------------------------- */
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

/* -------------------------------------------------------------------------- */
/* Security Group (open for testing)                                          */
/* -------------------------------------------------------------------------- */
resource "aws_security_group" "open_sg" {
  name        = "open-sg-${random_string.suffix.result}"
  description = "Open SG for testing - all ingress/egress allowed"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

/* -------------------------------------------------------------------------- */
/* S3 bucket for scripts, artifacts and data lake                             */
/* -------------------------------------------------------------------------- */
resource "aws_s3_bucket" "scripts" {
  bucket        = "pipeline-scripts-${random_string.suffix.result}"
  force_destroy = true
}

/* -------------------------------------------------------------------------- */
/* Common Lambda Layer (TEST)                                                 */
/* -------------------------------------------------------------------------- */

resource "local_file" "common_layer_code" {
  filename = "${path.module}/layer/python/common.py"

  content = <<-EOF
def helper():
    return "Hello from TEST layer"
EOF
}

resource "terraform_data" "prepare_dist" {
  provisioner "local-exec" {
    command = "mkdir -p ${path.module}/dist"
  }
}

data "archive_file" "common_layer_zip" {
  type        = "zip"
  source_dir  = "${path.module}/layer"
  output_path = "${path.module}/dist/common_layer.zip"

  depends_on = [
    local_file.common_layer_code,
    terraform_data.prepare_dist
  ]
}

/* Upload layer zip to S3 */
resource "aws_s3_object" "common_layer_zip" {
  bucket = aws_s3_bucket.scripts.id
  key    = "layer/common_layer.zip"

  source = data.archive_file.common_layer_zip.output_path
  etag   = data.archive_file.common_layer_zip.output_md5

  depends_on = [
    data.archive_file.common_layer_zip
  ]
}

/* -------------------------------------------------------------------------- */
/* Lambda Layer Version                                                       */
/* -------------------------------------------------------------------------- */

resource "aws_lambda_layer_version" "common" {
  layer_name          = "common-layer-${random_string.suffix.result}"

  s3_bucket = aws_s3_bucket.scripts.id
  s3_key    = aws_s3_object.common_layer_zip.key

  compatible_runtimes = ["python3.9"]

  source_code_hash = data.archive_file.common_layer_zip.output_base64sha256

  depends_on = [
    aws_s3_object.common_layer_zip
  ]
}
/* -------------------------------------------------------------------------- */
/* IAM Roles & Policy Attachments (Lambda & Glue)                             */
/* -------------------------------------------------------------------------- */
resource "aws_iam_role" "lambda_role" {
  name = "lambda-role-${random_string.suffix.result}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_admin" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

/* Glue role */
resource "aws_iam_role" "glue_role" {
  name = "glue-role-${random_string.suffix.result}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "glue.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy_attachment" "glue_admin" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

/* -------------------------------------------------------------------------- */
/* Lambda Functions (Producer & Streamer) – TEST artifacts                    */
/* -------------------------------------------------------------------------- */
# Producer Lambda code
resource "local_file" "producer_lambda_code" {
  filename = "${path.module}/src/producer_lambda.py"
  content  = <<-EOF
def lambda_handler(event, context):
    return {"statusCode": 200, "body": "Producer TEST"}
EOF
}

data "archive_file" "producer_lambda_zip" {
  type        = "zip"
  source_file = local_file.producer_lambda_code.filename
  output_path = "${path.module}/dist/producer_lambda.zip"
}

resource "aws_s3_object" "producer_lambda_zip" {
  bucket = aws_s3_bucket.scripts.id
  key    = "lambda/producer_lambda.zip"
  source = data.archive_file.producer_lambda_zip.output_path
  etag   = data.archive_file.producer_lambda_zip.output_md5
}

resource "aws_lambda_function" "producer" {
  function_name    = "producer-${random_string.suffix.result}"
  s3_bucket        = aws_s3_bucket.scripts.id
  s3_key           = aws_s3_object.producer_lambda_zip.key
  source_code_hash = data.archive_file.producer_lambda_zip.output_base64sha256
  handler          = "producer_lambda.lambda_handler"
  runtime          = "python3.9"
  timeout          = var.lambda_timeout
  memory_size      = 256
  role             = aws_iam_role.lambda_role.arn
  layers           = [aws_lambda_layer_version.common.arn]

  depends_on = [
    aws_s3_object.producer_lambda_zip,
    aws_lambda_layer_version.common
  ]
}

# Streamer Lambda code
resource "local_file" "streamer_lambda_code" {
  filename = "${path.module}/src/streamer_lambda.py"
  content  = <<-EOF
def lambda_handler(event, context):
    return {"statusCode": 200, "body": "Streamer TEST"}
EOF
}

data "archive_file" "streamer_lambda_zip" {
  type        = "zip"
  source_file = local_file.streamer_lambda_code.filename
  output_path = "${path.module}/dist/streamer_lambda.zip"
}

resource "aws_s3_object" "streamer_lambda_zip" {
  bucket = aws_s3_bucket.scripts.id
  key    = "lambda/streamer_lambda.zip"
  source = data.archive_file.streamer_lambda_zip.output_path
  etag   = data.archive_file.streamer_lambda_zip.output_md5
}

resource "aws_lambda_function" "streamer" {
  function_name    = "streamer-${random_string.suffix.result}"
  s3_bucket        = aws_s3_bucket.scripts.id
  s3_key           = aws_s3_object.streamer_lambda_zip.key
  source_code_hash = data.archive_file.streamer_lambda_zip.output_base64sha256
  handler          = "streamer_lambda.lambda_handler"
  runtime          = "python3.9"
  timeout          = var.lambda_timeout
  memory_size      = 256
  role             = aws_iam_role.lambda_role.arn
  layers           = [aws_lambda_layer_version.common.arn]

  depends_on = [
    aws_s3_object.streamer_lambda_zip,
    aws_lambda_layer_version.common
  ]
}

/* -------------------------------------------------------------------------- */
/* SQS Queue (for Producer -> Streamer)                                      */
/* -------------------------------------------------------------------------- */
resource "aws_sqs_queue" "pipeline_queue" {
  name = "pipeline-queue-${random_string.suffix.result}"
}

/* -------------------------------------------------------------------------- */
/* Event Source Mapping (Streamer Lambda <- SQS)                               */
/* -------------------------------------------------------------------------- */
resource "aws_lambda_event_source_mapping" "sqs_to_streamer" {
  event_source_arn = aws_sqs_queue.pipeline_queue.arn
  function_name    = aws_lambda_function.streamer.arn
  batch_size       = 10
}

/* -------------------------------------------------------------------------- */
/* RDS Subnet Group (uses default subnets)                                   */
/* -------------------------------------------------------------------------- */
resource "aws_db_subnet_group" "datalake" {
  name        = "datalake-subnet-${random_string.suffix.result}"
  subnet_ids  = data.aws_subnets.default.ids
  description = "Subnet group for RDS in default VPC"
}

/* -------------------------------------------------------------------------- */
/* Random password for RDS (no disallowed characters)                        */
/* -------------------------------------------------------------------------- */
resource "random_password" "db_password" {
  length  = 16
  special = false
}

/* -------------------------------------------------------------------------- */
/* RDS PostgreSQL Instance (publicly accessible for testing)                 */
/* -------------------------------------------------------------------------- */
resource "aws_db_instance" "postgres" {
  identifier             = "postgres-${random_string.suffix.result}"
  engine                 = "postgres"
  engine_version         = "15"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  username               = var.db_username
  password               = random_password.db_password.result
  publicly_accessible    = true
  skip_final_snapshot    = true
  vpc_security_group_ids = [aws_security_group.open_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.datalake.name
}

/* -------------------------------------------------------------------------- */
/* Glue Scripts (TEST) – one per job                                          */
/* -------------------------------------------------------------------------- */
# landing_ingest
resource "local_file" "glue_landing_ingest_script" {
  filename = "${path.module}/glue_scripts/landing_ingest.py"
  content  = <<-EOF
print("TEST script for landing_ingest")
EOF
}

resource "aws_s3_object" "glue_landing_ingest_script_obj" {
  bucket = aws_s3_bucket.scripts.id
  key    = "glue/landing_ingest.py"
  source = local_file.glue_landing_ingest_script.filename
}

# ecommerce_processing
resource "local_file" "glue_ecommerce_processing_script" {
  filename = "${path.module}/glue_scripts/ecommerce_processing.py"
  content  = <<-EOF
print("TEST script for ecommerce_processing")
EOF
}

resource "aws_s3_object" "glue_ecommerce_processing_script_obj" {
  bucket = aws_s3_bucket.scripts.id
  key    = "glue/ecommerce_processing.py"
  source = local_file.glue_ecommerce_processing_script.filename
}

# quality_audit
resource "local_file" "glue_quality_audit_script" {
  filename = "${path.module}/glue_scripts/quality_audit.py"
  content  = <<-EOF
print("TEST script for quality_audit")
EOF
}

resource "aws_s3_object" "glue_quality_audit_script_obj" {
  bucket = aws_s3_bucket.scripts.id
  key    = "glue/quality_audit.py"
  source = local_file.glue_quality_audit_script.filename
}

# silver_to_gold
resource "local_file" "glue_silver_to_gold_script" {
  filename = "${path.module}/glue_scripts/silver_to_gold.py"
  content  = <<-EOF
print("TEST script for silver_to_gold")
EOF
}

resource "aws_s3_object" "glue_silver_to_gold_script_obj" {
  bucket = aws_s3_bucket.scripts.id
  key    = "glue/silver_to_gold.py"
  source = local_file.glue_silver_to_gold_script.filename
}

# rds_load
resource "local_file" "glue_rds_load_script" {
  filename = "${path.module}/glue_scripts/rds_load.py"
  content  = <<-EOF
print("TEST script for rds_load")
EOF
}

resource "aws_s3_object" "glue_rds_load_script_obj" {
  bucket = aws_s3_bucket.scripts.id
  key    = "glue/rds_load.py"
  source = local_file.glue_rds_load_script.filename
}

/* -------------------------------------------------------------------------- */
/* Glue Jobs (5) – each uses its TEST script                                   */
/* -------------------------------------------------------------------------- */
resource "aws_glue_job" "landing_ingest" {
  name     = "glue-landing-ingest-${random_string.suffix.result}"
  role_arn = aws_iam_role.glue_role.arn
  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.scripts.bucket}/${aws_s3_object.glue_landing_ingest_script_obj.key}"
    python_version  = "3"
  }
  max_retries = 0
  timeout     = 10
}

resource "aws_glue_job" "ecommerce_processing" {
  name     = "glue-ecommerce-processing-${random_string.suffix.result}"
  role_arn = aws_iam_role.glue_role.arn
  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.scripts.bucket}/${aws_s3_object.glue_ecommerce_processing_script_obj.key}"
    python_version  = "3"
  }
  max_retries = 0
  timeout     = 10
}

resource "aws_glue_job" "quality_audit" {
  name     = "glue-quality-audit-${random_string.suffix.result}"
  role_arn = aws_iam_role.glue_role.arn
  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.scripts.bucket}/${aws_s3_object.glue_quality_audit_script_obj.key}"
    python_version  = "3"
  }
  max_retries = 0
  timeout     = 10
}

resource "aws_glue_job" "silver_to_gold" {
  name     = "glue-silver-to-gold-${random_string.suffix.result}"
  role_arn = aws_iam_role.glue_role.arn
  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.scripts.bucket}/${aws_s3_object.glue_silver_to_gold_script_obj.key}"
    python_version  = "3"
  }
  max_retries = 0
  timeout     = 10
}

resource "aws_glue_job" "rds_load" {
  name     = "glue-rds-load-${random_string.suffix.result}"
  role_arn = aws_iam_role.glue_role.arn
  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.scripts.bucket}/${aws_s3_object.glue_rds_load_script_obj.key}"
    python_version  = "3"
  }
  max_retries = 0
  timeout     = 10
}

/* -------------------------------------------------------------------------- */
/* Step Functions IAM Role                                                    */
/* -------------------------------------------------------------------------- */
resource "aws_iam_role" "step_functions_role" {
  name = "step-functions-role-${random_string.suffix.result}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "states.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "step_functions_admin" {
  role       = aws_iam_role.step_functions_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

/* -------------------------------------------------------------------------- */
/* Step Functions State Machine                                               */
/* -------------------------------------------------------------------------- */
resource "aws_sfn_state_machine" "etl_state_machine" {
  name     = "etl-step-function-${random_string.suffix.result}"
  role_arn = aws_iam_role.step_functions_role.arn

  definition = jsonencode({
    Comment = "Data lake ETL orchestrator"
    StartAt = "ProducerLambda"

    States = {

      ProducerLambda = {
        Type     = "Task"
        Resource = aws_lambda_function.producer.arn
        Next     = "StreamerLambda"
      }

      StreamerLambda = {
        Type     = "Task"
        Resource = aws_lambda_function.streamer.arn
        Next     = "LandingIngestJob"
      }

      LandingIngestJob = {
        Type     = "Task"
        Resource = "arn:aws:states:::glue:startJobRun.sync"

        Parameters = {
          JobName = aws_glue_job.landing_ingest.name

          Arguments = {
            "--CONFIG_PATH" = local.config_path
            "--DEPS_PATH"   = local.deps_path
          }
        }

        Next = "EcommerceProcessingJob"
      }

      EcommerceProcessingJob = {
        Type     = "Task"
        Resource = "arn:aws:states:::glue:startJobRun.sync"

        Parameters = {
          JobName = aws_glue_job.ecommerce_processing.name

          Arguments = {
            "--CONFIG_PATH" = local.config_path
            "--DEPS_PATH"   = local.deps_path
          }
        }

        Next = "QualityAuditJob"
      }

      QualityAuditJob = {
        Type     = "Task"
        Resource = "arn:aws:states:::glue:startJobRun.sync"

        Parameters = {
          JobName = aws_glue_job.quality_audit.name

          Arguments = {
            "--CONFIG_PATH" = local.config_path
            "--DEPS_PATH"   = local.deps_path
          }
        }

        Next = "SilverToGoldJob"
      }

      SilverToGoldJob = {
        Type     = "Task"
        Resource = "arn:aws:states:::glue:startJobRun.sync"

        Parameters = {
          JobName = aws_glue_job.silver_to_gold.name

          Arguments = {
            "--CONFIG_PATH" = local.config_path
            "--DEPS_PATH"   = local.deps_path
          }
        }

        Next = "RdsLoadJob"
      }

      RdsLoadJob = {
        Type     = "Task"
        Resource = "arn:aws:states:::glue:startJobRun.sync"

        Parameters = {
          JobName = aws_glue_job.rds_load.name

          Arguments = {
            "--CONFIG_PATH" = local.config_path
            "--DEPS_PATH"   = local.deps_path
          }
        }

        End = true
      }
    }
  })
}
/* -------------------------------------------------------------------------- */
/* Athena Workgroup                                                          */
/* -------------------------------------------------------------------------- */
resource "aws_athena_workgroup" "datalake_wg" {
  name = "athena-wg-${random_string.suffix.result}"
  configuration {
    enforce_workgroup_configuration = true
    result_configuration {
      output_location = "s3://${aws_s3_bucket.scripts.bucket}/athena-results/"
    }
  }
}
