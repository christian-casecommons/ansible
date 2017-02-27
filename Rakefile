#!/usr/bin/env ruby
require "rake"

## requires ###############################################

require "yaml"
require "capybara"
require "capybara/dsl"
require "selenium-webdriver"
require "net/http"

## constants ##############################################

TIMEOUT = 300
PATH_DOWNLOADS = "/tmp/downloads"

## methods ################################################

# executes shell command w/login profile
def bash cmd
  %x{ bash --login -c "#{ cmd }" }
end

def downloads
  Dir["/tmp/downloads/*"]
end

def downloaded?
  !downloading? && downloads.any?
end

def downloading?
  downloads.grep(/\.crdownload$/).any?
end

def clear_downloads
  FileUtils.rm_f(downloads)
end

## tasks ##################################################

task :init do
  @__init_capybara__ ||= begin
    include Capybara::DSL
    Capybara.register_driver :selenium do |app|
      Capybara::Selenium::Driver.new(
        app,
        :browser => :chrome,
        #url: "http://localhost:4444/wd/hub",
        prefs: {
          download: {
            default_directory: '/tmp/downloads'
          }
        }
      )
    end
    Capybara.javascript_driver = :selenium
    Capybara.run_server = false
    Capybara.current_driver = :selenium
  end
end

namespace :wordpress do
  desc "import a wordpress site"
  task :import, [ :host, :user, :password, :import ] => [ :init ] do | _, arguments |
    # spinup standalone container
    bash %{
      mkdir -p /tmp/selenium 2>/dev/null

      docker swarm init 2>/dev/null
      docker service create \
      --replicas 1 \
      --name mysql \
      --env MYSQL_ROOT_PASSWORD=mypassword \
      --env MYSQL_DATABASE=wordpress \
      --mount type=volume,source=mysql,destination=/var/lib/mysql \
      --publish 3306:3306 \
        mysql:5.7 2>/dev/null

      mysql \
        -uroot \
        -P 3306 \
        -h 127.0.0.1 \
        -pmypassword \
        -e '
          DROP DATABASE IF EXISTS wordpress_export;
          CREATE DATABASE wordpress_export
        '

      docker service rm wordpress_export
      docker service create \
        --replicas 1 \
        --name wordpress_export \
        -e WORDPRESS_DB_HOST=192.168.1.97 \
        -e WORDPRESS_DB_PASSWORD=mypassword \
        -e WORDPRESS_DB_NAME=wordpress_export \
        --publish 8080:80 \
          wordpress 2>/dev/null
    }

    begin
      Net::HTTP.get URI( "http://#{ arguments[:host] }" )
    rescue
      sleep 1
      retry
    end

    visit "http://#{ arguments[:host] }/wp-admin/install.php?step=1"
    fill_in :user_login, with: arguments[:user]
    fill_in :"pass1-text", with: arguments[:password]
    fill_in :admin_email, with: "test@test.com"
    check :pw_weak
    click_button "submit"

    visit "http://#{ arguments[:host] }/wp-admin/import.php"
    ( find "a[data-slug='wordpress-importer']" ).click

    begin
      ( find_link "Run Importer" ).click
    rescue
      sleep 1
      retry
    end

    attach_file :upload, arguments[:import]
    click_button :submit

    check "import-attachments"
    ( find "input[type='text']" ).set "importer"
    ( find :css, "input.button" ).click

    sleep 300
  end

  desc "exports a wordpress site"
  task :export, [ :host, :user, :password ] => [ :init ] do | _, arguments |
    # spinup standalone container
    bash %{
      mkdir -p /tmp/selenium 2>/dev/null

      docker swarm init 2>/dev/null
      #docker service create \
      #  --replicas 1 \
      #  --name selenium \
      #  --publish 4444:4444 \
      #  --publish 5901:5900 \
      #  --mount type=tmpfs,destination=/dev/shm \
      #    selenium/standalone-chrome-debug:3.0.1-fermium 2>/dev/null

      mkdir -p /tmp/downloads 2>/dev/null
    }
    clear_downloads

    visit "http://#{ arguments[:host] }/wp-admin/export.php"
    fill_in :user_login, with: arguments[:user]
    fill_in :user_pass, with: arguments[:password]
    click_button "wp-submit"
    click_button "submit"

    Timeout.timeout(TIMEOUT) do
      sleep 0.1 until downloaded?
    end
  end
end

namespace :ansible do
  desc "shows hiera for host"
  task :facts, [ :host ] do | t, arguments |
    puts bash( "./bin/extends --facts=#{ arguments[:host] } ansible -i./hosts" )
  end

  desc "shows groups that host belongs to"
  task :groups, [ :host ] do | t, arguments |
    puts bash( "./bin/extends --host=#{ arguments[:host] } ansible -i./hosts" )
  end

  desc "shows hosts that belong to group"
  task :hosts, [ :group ] do | t, arguments |
    puts bash( "./bin/extends --group=#{ arguments[:group] } ansible -i./hosts" )
  end

  desc "generates docker nodes from inventory file"
  task :nodes, [ :inventory ] do | _, arguments |
    port = 2221
    inventory ||= arguments[:inventory]
    content = File.read inventory
    matches = ( content.scan /^.+?ansible_host.+$/ )

    %x{
      docker network rm ansible.gwambia
      docker network create -d bridge --subnet 172.25.0.0/16 ansible.gwambia
    }

    # first we iterate through matches so that we can get host
    # name and address
    hosts = matches.map do | line |
      {
        name: ( line.match /^(?<name>.+?)\s/ )['name'],
        address: ( line.match r = /ansible_host\s*?=\s*?(?<host>.+?)(\s|$)/ )['host'],
      }
    end
    hosts.each do | host |
      facts = YAML.load `rake ansible:facts[#{ host }]`
      puts facts
      exit
      # replace host with loopback address and port
      content.gsub! /ansible_host=#{ host[:address] }/, " ansible_host=127.0.0.1 ansible_port=#{ port += 1 } "

      # determine ubuntu version based upon group membership
      groups = `rake ansible:groups[#{ host[:name] }]`.split "\n"
      tag = groups.include?( "xenial" ) && "16.04" || "14.04.5"

      # launch docker container
      fork do
        exec %{
          docker rm -f #{ name } > /dev/null 2>&1
          docker run \
            -it \
            -d \
            --name #{ name } \
            --publish #{ port }:22 \
            --volume $SSH_AUTH_SOCK:/ssh-agent \
            --env SSH_AUTH_SOCK="$SSH_AUTH_SOCK" \
            --network ansible.gwambia \
            ubuntu:#{ tag } /bin/bash -l

          docker exec #{ name } bash -c "
            apt update
            apt install -y \
              sudo vim ssh telnet net-tools python-minimal
            service ssh start
          "

          pub=`cat ~/.ssh/id_rsa.pub`
          docker exec #{ name } bash -c "
            mkdir ~/.ssh; echo '$pub' >> ~/.ssh/authorized_keys
          "
        }
      end
    end
    Process.wait

    puts content
    exit

    # finally write inventory.development
    File.write "#{ inventory }.development", content
  end
end
