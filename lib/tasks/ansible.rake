#!/usr/bin/env ruby
require "rake"
require "yaml"
require "deep_merge"

## methods ################################################

# executes shell command w/login profile
def bash cmd
  %x{ bash --login -c "#{ cmd }" }
end

# command line flag parser
def options
  @__options__ ||= begin
    options = { }

    # define our options parser and flags we are explicitly
    # looking for
    parser = OptionParser.new do |opts|
      opts.on("--logs") do |v|
        options[:logs] = true
      end
    end.parse!

    # finally return options to caller
    options
  end
end

# executes command within bash as opposed to shell
def command cmd
  %x{ bash -c "#{ cmd }" }
end

def pick_file path
  if  File.exists?( file = "#{ path }" ) ||
      File.exists?( file = "#{ path }.yml" ) ||
      File.exists?( file = "#{ path }.yaml" )
    file
  end
end

## tasks ##################################################

namespace :ansible do
  desc "shows hiera for host"
  task :facts, [ :ip ] do | t, arguments |
    ip = arguments[:ip] || %x{
      ip route get 1 | awk '{ print $NF; exit }'
    }
    home = ENV["ANSIBLE_HOME"] || "/etc/ansible"

    begin
      puts File.read "#{ home }/host_vars/host-#{ ip }"
    rescue => e
      logs "failed to open host file", file: "#{ home }/host_vars/host-#{ ip }"
      fail e
    end
  end

  desc "builds heira-complete facts for every host"
  task :build_facts, [ :path ] do | _, arguments |
    # path is containing dir for ansible hosts, config, vars, etc
    path = arguments[:path] || "/etc/ansible"
    logs "building facts", path: path

    # write dynamic inventory to path or default
    content = %x{
      ./plugins/hieransible/ec2.py \
        | HOSTS_FILE=./hosts ./plugins/hieransible/casecommons.rb --ini
    }

    if $?.success?
      File.write "#{ path }/hosts", content
      logs "wrote host file", path: "#{ path }/hosts",
                            content: content.gsub( /\n/, "" )
    else
      logs "failed to execute plugins", content: content
    end

    # get all hosts
    content = File.read "#{ path }/hosts"
    hosts = ( content.scan /^([\w\.-]+?)\s/ )
      .flatten
      .uniq
    logs "parsed hosts", hosts: hosts

    # find all groups associated to a host

    blocks = content.scan /(?<group>[\w\.\:-]+?)\](?<hosts>.+?)(\[|\Z)/m
    hosts.each do | host |
      groups = [ ]
      blocks.each do | block |
        group, block = block
        groups << group if block.include? host
      end
      logs "found host's groups", host: host, groups: groups

      # build host_vars file for host performing deep merges against
      # groups that host belongs to
      facts = { }

      # iterate through groups, check if a group_vars file exists
      groups = %w{ all } + groups
      groups.each do | candidate |
        if f = pick_file( "./group_vars/#{ candidate }" )
          logs "found group_vars candidate", group: candidate
          facts.deep_merge!( YAML.load File.read( f ), overwite_arrays: true )
        end
      end

      # check if hosts_vars file exists and perform final deep merge
      if f = pick_file( "./host_vars/__#{ host }__" )
        facts.deep_merge!( YAML.load File.read( f ), overwite_arrays: true )
      end

      # finally write deep merged facts to hosts vars
      # for host
      File.write "#{ path }/host_vars/#{ host }", facts.to_yaml
    end
  end

  desc "generates docker nodes from inventory file"
  task :nodes, [ :inventory ] do | t, arguments |
    port = 2221
    content = File.read arguments[:inventory]
    ( content.scan /^.+?ansible_host.+$/ ).each do | line |
      name = ( line.match /^(?<name>.+?)\s/ )['name']
      host = ( line.match r = /ansible_host\s*?=\s*?(?<host>.+?)(\s|$)/ )['host']

      # replace host with loopback address and port
      replace = line.sub /#{ r }/, " ansible_host=127.0.0.1 ansible_port=#{ port += 1 } "
      content.sub! line, replace

      # determine ubuntu version based upon group membership
      groups = `rake ansible:groups[#{ name }]`.split "\n"
      tag = groups.include?( "xenial" ) && "16.04" || "14.04.3"

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
          exit 0
        }
      end
    end
    Process.wait

    # finally write inventory.development
    File.write "#{ arguments[:inventory] }.development", content
  end

  desc "bootstraps a new instance with ansible requirements and users"
  task :bootstrap, [ :host ] do | _, arguments |
    exec %{
      ansible-playbook ./playbooks/bootstrap.yml \
        -vv \
        -uubuntu \
        -i"#{ arguments[:host] },"
    }
  end
end