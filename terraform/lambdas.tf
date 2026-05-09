data "aws_iam_instance_profile" "lab" {
  name = "LabInstanceProfile"
}

data "archive_file" "integration_test" {
  type        = "zip"
  source_dir  = "${path.module}/../scripts/lambdas/integration_test"
  output_path = "${path.module}/../scripts/lambdas/integration_test.zip"
}

data "archive_file" "deploy_qa" {
  type        = "zip"
  source_file = "${path.module}/../scripts/lambdas/deploy_qa/lambda_function.py"
  output_path = "${path.module}/../scripts/lambdas/deploy_qa.zip"
}

resource "aws_lambda_function" "integration_test" {
  filename         = data.archive_file.integration_test.output_path
  function_name    = "detailsnap-integration-test"
  role             = data.aws_iam_role.lab.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  timeout          = 900

  source_code_hash = data.archive_file.integration_test.output_base64sha256

  environment {
    variables = {
      INSTANCE_PROFILE_ARN = data.aws_iam_instance_profile.lab.arn
      SSM_PREFIX           = "/detailsnap/smoke-test"
    }
  }
}

resource "aws_lambda_function" "deploy_qa" {
  filename         = data.archive_file.deploy_qa.output_path
  function_name    = "detailsnap-deploy-qa"
  role             = data.aws_iam_role.lab.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  timeout          = 60

  source_code_hash = data.archive_file.deploy_qa.output_base64sha256
}
