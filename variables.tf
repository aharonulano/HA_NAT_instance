variable "profile_name" {
  description = "(Required) profile login configured by sso or aws configured"
  type        = string
  sensitive   = true
  # default     =
}

variable "account" {
  description = "(Required) account id for tf code to run on"
  type        = string
  # default     =
  sensitive   = true
}

variable "aws_region" {
  description = "(Required) in which region to run"
  type        = string
  default     = "eu-west-1"
}
