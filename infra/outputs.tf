output "scripts_bucket_name" {
  description = "Name of the S3 bucket that stores scripts and data lake"
  value       = aws_s3_bucket.scripts.bucket
}

/* Lambda outputs */
output "producer_lambda_name" {
  value = aws_lambda_function.producer.function_name
}
output "producer_lambda_arn" {
  value = aws_lambda_function.producer.arn
}
output "producer_lambda_zip_s3_uri" {
  value = "s3://${aws_s3_bucket.scripts.bucket}/${aws_s3_object.producer_lambda_zip.key}"
}

output "streamer_lambda_name" {
  value = aws_lambda_function.streamer.function_name
}
output "streamer_lambda_arn" {
  value = aws_lambda_function.streamer.arn
}
output "streamer_lambda_zip_s3_uri" {
  value = "s3://${aws_s3_bucket.scripts.bucket}/${aws_s3_object.streamer_lambda_zip.key}"
}

/* Layer output */
output "common_layer_arn" {
  value = aws_lambda_layer_version.common.arn
}
output "common_layer_zip_s3_uri" {
  value = "s3://${aws_s3_bucket.scripts.bucket}/${aws_s3_object.common_layer_zip.key}"
}

/* SQS */
output "sqs_queue_url" {
  value = aws_sqs_queue.pipeline_queue.id
}
output "sqs_queue_arn" {
  value = aws_sqs_queue.pipeline_queue.arn
}

/* RDS */
output "rds_endpoint" {
  value = aws_db_instance.postgres.endpoint
}
output "rds_port" {
  value = aws_db_instance.postgres.port
}
output "rds_username" {
  value = var.db_username
}
output "rds_database_name" {
  value = var.db_name
}

/* Glue job outputs */
output "glue_landing_ingest_name" {
  value = aws_glue_job.landing_ingest.name
}
output "glue_landing_ingest_arn" {
  value = aws_glue_job.landing_ingest.arn
}
output "glue_landing_ingest_script_s3_uri" {
  value = "s3://${aws_s3_bucket.scripts.bucket}/${aws_s3_object.glue_landing_ingest_script_obj.key}"
}

output "glue_ecommerce_processing_name" {
  value = aws_glue_job.ecommerce_processing.name
}
output "glue_ecommerce_processing_arn" {
  value = aws_glue_job.ecommerce_processing.arn
}
output "glue_ecommerce_processing_script_s3_uri" {
  value = "s3://${aws_s3_bucket.scripts.bucket}/${aws_s3_object.glue_ecommerce_processing_script_obj.key}"
}



output "glue_silver_to_gold_name" {
  value = aws_glue_job.silver_to_gold.name
}
output "glue_silver_to_gold_arn" {
  value = aws_glue_job.silver_to_gold.arn
}
output "glue_silver_to_gold_script_s3_uri" {
  value = "s3://${aws_s3_bucket.scripts.bucket}/${aws_s3_object.glue_silver_to_gold_script_obj.key}"
}

output "glue_rds_load_name" {
  value = aws_glue_job.rds_load.name
}
output "glue_rds_load_arn" {
  value = aws_glue_job.rds_load.arn
}
output "glue_rds_load_script_s3_uri" {
  value = "s3://${aws_s3_bucket.scripts.bucket}/${aws_s3_object.glue_rds_load_script_obj.key}"
}

/* Step Functions */
output "step_function_arn" {
  value = aws_sfn_state_machine.etl_state_machine.arn
}
output "step_function_name" {
  value = aws_sfn_state_machine.etl_state_machine.name
}

/* Athena */
output "athena_workgroup_name" {
  value = aws_athena_workgroup.datalake_wg.name
}
