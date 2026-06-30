variable "key_name" {
  description = "Addosser-key"
}

variable "db_username" {
  description = "Database username"
  default     = "drupal"
}

variable "db_password" {
  description = "Database password"
  sensitive   = true
}
