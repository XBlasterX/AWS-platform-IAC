module "network" {
  source = "../../modules/network"

  vpc_cidr            = var.vpc_cidr
  public_subnet_cidr  = var.public_subnet_cidr
  private_subnet_cidr = var.private_subnet_cidr
  availability_zone   = var.availability_zone
}

module "security" {
  source = "../../modules/security"

  vpc_id = module.network.vpc_id
}

module "iam" {
  source                  = "../../modules/iam"
  flow_log_logs_group_arn = module.monitoring.flow_log_group_arn
}

module "compute" {
  source                    = "../../modules/compute"
  instance_type             = "t3.micro"
  ec2_instance_profile_name = module.iam.ec2_instance_profile_name
  ec2_security_group_ids    = module.security.ec2_security_group_ids
  target_group_arns         = [module.load_balancer.target_group_arns]
  depends_on                = [module.load_balancer]
  private_subnet_ids        = module.network.private_subnet_ids
}

module "load_balancer" {
  source                = "../../modules/load_balancer"
  vpc_id                = module.network.vpc_id
  public_subnet_ids     = module.network.public_subnet_ids
  alb_security_group_id = module.security.alb_security_group_id
}

module "monitoring" {
  source                  = "../../modules/monitoring"
  alb_arn_suffix          = module.load_balancer.alb_arn_suffix
  target_group_arn_suffix = module.load_balancer.target_group_arn_suffix
  aws_region              = var.aws_region
}
