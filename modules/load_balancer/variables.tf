variable "vpc_id" {
  type        = string
  description = "vpc_id"
}
variable "public_subnet_ids" {
  type        = list(string)
  description = "subnet_ids"
}
variable "alb_security_group_id" {
  type        = string
  description = "alb security"
}
