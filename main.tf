module "cost_optimizer_prod" {
  source              = "./Modules/Under-Utilized-Resources"
  region              = var.region
  email_endpoint      = var.email_endpoint
  lambda_function_name = var.lambda_function_name
}