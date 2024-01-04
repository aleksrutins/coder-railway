terraform {
  required_providers {
		coder = {
			source = "coder/coder"
		}
    railway = {
      source = "terraform-community-providers/railway"
      version = "~> 0.2.0"
    }
  }
}

locals {
  username = data.coder_workspace.me.owner
}

variable "railway_token" {
  type = string
  description = "Railway access token"
}

variable "railway_project" {
  type = string
  description = "Project ID to deploy services on"
}

variable "railway_environment" {
	type = string
	description = "Environment ID to set variables on"
}

provider "coder" {}

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}

provider "railway" {
  token = var.railway_token
}

resource "coder_agent" "dev" {
	arch = "amd64"
	os = "linux"

	startup_script = <<-EOT
		set -e

    # install and start code-server
    curl -fsSL https://code-server.dev/install.sh | sh -s -- --method=standalone --prefix=/tmp/code-server --version 4.19.1
    /tmp/code-server/bin/code-server --auth none --port 13337 >/tmp/code-server.log 2>&1 &
	EOT

	env = {
    GIT_AUTHOR_NAME     = "${data.coder_workspace.me.owner}"
    GIT_COMMITTER_NAME  = "${data.coder_workspace.me.owner}"
    GIT_AUTHOR_EMAIL    = "${data.coder_workspace.me.owner_email}"
    GIT_COMMITTER_EMAIL = "${data.coder_workspace.me.owner_email}"
  }

	# The following metadata blocks are optional. They are used to display
  # information about your workspace in the dashboard. You can remove them
  # if you don't want to display any information.
  # For basic resources, you can use the `coder stat` command.
  # If you need more control, you can write your own script.
  metadata {
    display_name = "CPU Usage"
    key          = "0_cpu_usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "RAM Usage"
    key          = "1_ram_usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Home Disk"
    key          = "3_home_disk"
    script       = "coder stat disk --path $${HOME}"
    interval     = 60
    timeout      = 1
  }

  metadata {
    display_name = "CPU Usage (Host)"
    key          = "4_cpu_usage_host"
    script       = "coder stat cpu --host"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Memory Usage (Host)"
    key          = "5_mem_usage_host"
    script       = "coder stat mem --host"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Load Average (Host)"
    key          = "6_load_host"
    # get load avg scaled by number of cores
    script   = <<EOT
      echo "`cat /proc/loadavg | awk '{ print $1 }'` `nproc`" | awk '{ printf "%0.2f", $1/$2 }'
    EOT
    interval = 60
    timeout  = 1
  }

  metadata {
    display_name = "Swap Usage (Host)"
    key          = "7_swap_host"
    script       = <<EOT
      free -b | awk '/^Swap/ { printf("%.1f/%.1f", $3/1024.0/1024.0/1024.0, $2/1024.0/1024.0/1024.0) }'
    EOT
    interval     = 10
    timeout      = 1
  }
}

resource "coder_app" "code-server" {
  agent_id     = coder_agent.dev.id
  slug         = "code-server"
  display_name = "code-server"
  url          = "http://localhost:13337/?folder=/home/${local.username}"
  icon         = "/icon/code.svg"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://localhost:13337/healthz"
    interval  = 5
    threshold = 6
  }
}

resource "railway_service" "code_server" {
	name = "coder-${data.coder_workspace.me.owner}-${data.coder_workspace.me.name}"
	project_id = var.railway_project
	source_image = "ghcr.io/aleksrutins/coder-railway"
	root_directory = "build"
}

resource "railway_variable" "start_script" {
	service_id = railway_service.code_server.id
	environment_id = var.railway_environment
	name = "START_SCRIPT"
	value = base64encode(coder_agent.dev.init_script)
}

resource "railway_variable" "port" {
	service_id = railway_service.code_server.id
	environment_id = var.railway_environment
	name = "PORT"
	value = "13337"
}

resource "railway_variable" "token" {
	service_id = railway_service.code_server.id
	environment_id = var.railway_environment
	name = "CODER_AGENT_TOKEN"
	value = coder_agent.dev.token
}