locals {
  region                   = "eu-central-1"
  s3_bucket_name           = "tag-image-bucket"
  lamdas_path              = "./dist"
  get_status_and_tags_path = "${local.lamdas_path}/get-status-tags.zip"
  extract_tags_path        = "${local.lamdas_path}/extract-tags.zip"
  get_upload_link_path     = "${local.lamdas_path}/get-upload-link.zip"
}

provider "aws" {
  region = local.region
}

resource "aws_s3_bucket" "terraform_state" {
  bucket = "terraform-tag-image-bucket-state"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "versioning" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "encryption" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_dynamodb_table" "terraform_locks" {
  name         = "terraform_state_locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

terraform {
  backend "s3" {
    bucket         = "terraform-tag-image-bucket-state"
    key            = "global/s3/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "terraform_state_locks"
    encrypt        = true
  }
}

resource "aws_s3_bucket" "image_bucket" {
  bucket = local.s3_bucket_name
}

resource "aws_dynamodb_table" "tags_table" {
  name         = "TagsTable"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "uploadId"

  attribute {
    name = "uploadId"
    type = "S"
  }
}

resource "aws_iam_role" "lambda_role" {
  name = "lambda_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSLambdaExecute"
}

resource "aws_iam_policy" "rekognition_policy" {
  name        = "rekognitionPolicy"
  description = "Policy to allow Lambda to call Rekognition DetectLabels"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "rekognition:DetectLabels"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "rekognition_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.rekognition_policy.arn
}

resource "aws_iam_policy" "dynamodb_policy" {
  name        = "dynamodbPolicy"
  description = "Policy to allow Lambda to put items in DynamoDB"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "dynamodb:*"
        Resource = "${aws_dynamodb_table.tags_table.arn}"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "dynamodb_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.dynamodb_policy.arn
}


resource "aws_lambda_function" "get_upload_link" {
  function_name    = "getUploadLink"
  handler          = "index.getUploadLink"
  runtime          = "nodejs18.x"
  role             = aws_iam_role.lambda_role.arn
  filename         = local.get_upload_link_path
  source_code_hash = filebase64sha256(local.get_upload_link_path)
  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.image_bucket.bucket
      TABLE_NAME  = aws_dynamodb_table.tags_table.name
    }
  }
}

resource "aws_lambda_function" "extract_tags" {
  function_name    = "extractTags"
  handler          = "index.extractTags"
  runtime          = "nodejs18.x"
  role             = aws_iam_role.lambda_role.arn
  filename         = local.extract_tags_path
  source_code_hash = filebase64sha256(local.extract_tags_path)
  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.image_bucket.bucket
      TABLE_NAME  = aws_dynamodb_table.tags_table.name
    }
  }
}

resource "aws_lambda_function" "get_status_and_tags" {
  function_name    = "getStatusAndTags"
  handler          = "index.getStatusAndTags"
  runtime          = "nodejs18.x"
  role             = aws_iam_role.lambda_role.arn
  filename         = local.get_status_and_tags_path
  source_code_hash = filebase64sha256(local.get_status_and_tags_path)
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.tags_table.name
    }
  }
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.image_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.extract_tags.arn
    events              = ["s3:ObjectCreated:*"]
  }
}

resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.extract_tags.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.image_bucket.arn
}

resource "aws_iam_policy" "s3_presign_policy" {
  name        = "s3PresignPolicy"
  description = "Policy to allow Lambda to generate presigned URLs"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ]
        Resource = [
          "${aws_s3_bucket.image_bucket.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "s3_presign_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.s3_presign_policy.arn
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "TagImageAPI"
  description = "API for Tag Image application"
}

resource "aws_api_gateway_resource" "upload_link_resource" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "upload-link"
}

resource "aws_api_gateway_method" "upload_link_method" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.upload_link_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "upload_link_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.upload_link_resource.id
  http_method             = aws_api_gateway_method.upload_link_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.get_upload_link.invoke_arn
}

resource "aws_api_gateway_method" "status_tags_method" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.status_tags_resource.id
  http_method   = "GET"
  authorization = "NONE"
  request_parameters = {
    "method.request.querystring.uploadId" = true
  }
}

resource "aws_api_gateway_resource" "status_tags_resource" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "status-tags"
}

resource "aws_api_gateway_integration" "status_tags_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.status_tags_resource.id
  http_method             = aws_api_gateway_method.status_tags_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.get_status_and_tags.invoke_arn
  request_parameters = {
    "integration.request.querystring.uploadId" = "method.request.querystring.uploadId"
  }
}

resource "aws_lambda_permission" "api_gateway_upload_link" {
  statement_id  = "AllowAPIGatewayInvokeUploadLink"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_upload_link.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "api_gateway_status_tags" {
  statement_id  = "AllowAPIGatewayInvokeStatusTags"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_status_and_tags.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}


resource "aws_api_gateway_deployment" "api_deployment" {
  depends_on = [
    aws_api_gateway_integration.upload_link_integration,
    aws_api_gateway_integration.status_tags_integration
  ]
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = "prod"

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_rest_api.api.body,
      aws_api_gateway_rest_api.api.root_resource_id,
      aws_api_gateway_method.upload_link_method.id,
      aws_api_gateway_method.status_tags_method.id,
      aws_api_gateway_integration.upload_link_integration.id,
      aws_api_gateway_integration.status_tags_integration.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

output "rest_api_id" {
  value = aws_api_gateway_deployment.api_deployment.rest_api_id
}
