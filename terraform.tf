terraform {
  required_providers {
    sys = {
      source = "localhost/local/sys"
    }
  }
  required_version = ">= 0.13"
}

provider "sys" {
  log_level = "trace"
}

