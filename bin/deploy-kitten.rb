#!/usr/bin/env ruby
require "bundler/inline"

gemfile do
  source "https://rubygems.org"
  gem "sshkit"
end

require "sshkit"
require "sshkit/dsl"
require "stringio"
include SSHKit::DSL

SSH_SERVER = "ubuntu@3.67.113.666".freeze
APP_DOMAIN = "example.org".freeze

APP_NAME = "cat".freeze
DNS_PREFIX = "cat".freeze
APP_DIR = "/home/ubuntu/#{APP_NAME}/app/#{DNS_PREFIX}".freeze

SSHKit.config.output_verbosity = :debug # Optional: Increase verbosity for debugging

on SSH_SERVER do
  if test "[ ! -x /usr/bin/docker ]"
    execute "sudo apt-get update && sudo apt-get install -y curl" if test "[ ! -x /usr/bin/curl ]"
    execute :curl, "-fsSL https://get.docker.com -o /tmp/get-docker.sh"
    execute :sh, "/tmp/get-docker.sh"
    execute :sudo, :usermod, "-aG", :docker, "ubuntu"
    execute :rm, "/tmp/get-docker.sh"
  end

  if test "[ ! -f /home/ubuntu/traefik/docker-compose.yml ]"
    execute :mkdir, "-p /home/ubuntu/traefik"
  end

  within "/home/ubuntu/traefik" do
    docker_compose_content = <<~YML
      version: '2'
      services:
        reverse-proxy:
          image: ipepe/traefik
          restart: always
          network_mode: bridge
          ports:
            - "80:80"
            - "443:443"
            - "8080:8080" # The Web UI (enabled by --api)
          volumes:
            - /var/run/docker.sock:/var/run/docker.sock # So that Traefik can listen to the Docker events
          labels:
            - "traefik.enable=true"
            - "traefik.port=8080"
            - "traefik.frontend.rule=Host:traefik.#{APP_DOMAIN}"
    YML

    upload! StringIO.new(docker_compose_content), "/home/ubuntu/traefik/docker-compose.yml"
    execute :docker, :compose, :up, "-d"
  end

  execute :mkdir, "-p #{APP_DIR}"
  within APP_DIR do
    kitten_docker_compose = <<~YML
      version: '2'
      services:
        kitten:
          image: ipepe/kitten
          restart: always
          network_mode: bridge
          expose:
            - "80"
          labels:
            - "traefik.enable=true"
            - "traefik.port=80"
            - "traefik.frontend.rule=Host:#{DNS_PREFIX}.#{APP_DOMAIN}"
    YML

    upload! StringIO.new(kitten_docker_compose), "#{APP_DIR}/docker-compose.yml"

    stop_review_app_script = <<~SH
      #!/bin/bash
      docker compose down
    SH

    upload! StringIO.new(stop_review_app_script), "#{APP_DIR}/stop_review_app.sh"

    start_review_app_script = <<~SH
      #!/bin/bash
      docker compose up --build --remove-orphans -d
    SH

    upload! StringIO.new(start_review_app_script), "#{APP_DIR}/start_review_app.sh"

    execute :chmod, "+x #{APP_DIR}/stop_review_app.sh"
    execute :chmod, "+x #{APP_DIR}/start_review_app.sh"

    execute :sh, "#{APP_DIR}/start_review_app.sh"
  end

  puts "App is available at https://#{DNS_PREFIX}.#{APP_DOMAIN}"
end
