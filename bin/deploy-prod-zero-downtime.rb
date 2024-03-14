#!/usr/bin/env ruby
require "bundler/inline"

gemfile do
  source "https://rubygems.org"
  gem "sshkit"
  gem "activesupport"
end

require "active_support/all"
require "sshkit"
require "sshkit/dsl"
require "securerandom"

include SSHKit::DSL

SSH_SERVER = "ubuntu@3.67.113.67".freeze
APP_DOMAIN = "example.org".freeze

APP_NAME = "example".freeze
GIT_BRANCH = "main".freeze
DNS_PREFIX = "example".freeze
RELEASE_HASH = SecureRandom.hex(4)

APP_DIR = "/home/ubuntu/#{APP_NAME}/app/#{DNS_PREFIX}/#{RELEASE_HASH}".freeze
REPO_DIR = "/home/ubuntu/#{APP_NAME}/repo".freeze
GIT_ORIGIN = `git config --get remote.origin.url`.strip

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

    upload! StringIO.new(docker_compose_content), "docker-compose.yml"
    execute :docker, :compose, :up, "-d"
  end

  if test "[ -d #{REPO_DIR} ]"
    within REPO_DIR do
      execute :git, "remote set-url origin #{GIT_ORIGIN}"
      execute :git, "remote update --prune"
    end
  else
    if test "[ ! -f /home/ubuntu/.ssh/known_hosts ]"
      execute "ssh-keyscan github.com >> /home/ubuntu/.ssh/known_hosts"
    end
    execute :git, :clone, "--mirror", GIT_ORIGIN, REPO_DIR
  end

  execute :mkdir, "-p #{APP_DIR}"

  within REPO_DIR do
    execute :git, "archive #{GIT_BRANCH} | tar -x -f - -C #{APP_DIR}"
  end

  within APP_DIR do
    docker_compose_content = <<~YML
      version: '2.4'
      services:
        app_#{RELEASE_HASH}:
          environment:
            DB_HOST: db
            REDIS_URL: redis://redis:6379/1
            PUMA_WORKERS: 4
            DB_NAME: 'webapp'
            DB_USERNAME: 'webapp'
            DB_PASSWORD: 'Password1'
            SECRET_KEY_BASE: '1'
            RAILS_SERVE_STATIC_FILES: 'true'
          restart: always
          network_mode: bridge
          expose:
            - 3000
          build: .
          labels:
            - "traefik.enable=true"
            - "traefik.port=3000"
            - "traefik.frontend.rule=Host:#{DNS_PREFIX}.#{APP_DOMAIN}"
          links:
            - db
            - redis
          depends_on:
            - db
            - redis

        db:
          image: postgres:10
          network_mode: bridge
          expose:
            - 5432
          environment:
            POSTGRES_DB: webapp
            POSTGRES_USER: webapp
            POSTGRES_PASSWORD: Password1
          volumes:
            - /home/ubuntu/#{APP_NAME}/data/#{DNS_PREFIX}/db:/var/lib/postgresql/data

        redis:
          image: redis
          network_mode: bridge
          expose:
            - 6379
    YML

    upload! StringIO.new(docker_compose_content), "#{APP_DIR}/docker-compose.yml"

    stop_app_script = <<~SH
      #!/bin/bash
      docker compose down
    SH

    upload! StringIO.new(stop_app_script), "#{APP_DIR}/stop.sh"

    start_app_script = <<~SH
      #!/bin/bash

      set -e

      echo "Building and starting new container"#{'      '}
      docker compose up --build -d

      echo "With 60 seconds timeout check if new container has healthy status"
      timeout 60 bash -c 'while [[ "$(docker inspect -f {{.State.Health.Status}} $(docker compose ps -q app_#{RELEASE_HASH}))" != "healthy" ]]; do sleep 1; done'

      echo "Removing old containers"
      docker compose up --remove-orphans -d
    SH

    upload! StringIO.new(start_app_script), "#{APP_DIR}/start.sh"

    execute :chmod, "+x #{APP_DIR}/stop.sh"
    execute :chmod, "+x #{APP_DIR}/start.sh"

    execute :sh, "#{APP_DIR}/start.sh"
  end

  puts "App is available at https://#{DNS_PREFIX}.#{APP_DOMAIN}"
end
