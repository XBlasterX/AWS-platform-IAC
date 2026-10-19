output "alb_dns_name" {
  value       = module.load_balancer.dns_loadbalancer
  description = "Public DNS name of the Application Load Balancer"
}

output "vpc_id" {
  value       = module.network.vpc_id
  description = "ID of the created VPC"
}

output "public_subnet_ids" {
  value       = module.network.public_subnet_ids
  description = "IDs of the public subnets"
}

output "private_subnet_ids" {
  value       = module.network.private_subnet_ids
  description = "IDs of the private subnets"
}

output "asg_name" {
  value       = module.compute.asg_name
  description = "Name of the Auto Scaling Group"
}

output "cloudwatch_dashboard_name" {
  value       = "production-platform-dashboard"
  description = "Name of the CloudWatch observability dashboard"
}

