#!/usr/bin/env ruby
# Provides dynamic-host inclusion into hosts file
#
# usage:
# ansible -i/path/to/hosts

require "optparse"
require "json"
require "shellwords"
require "fileutils"
require "yaml"
require "deep_merge"
require "logger"
require "json"

## constants ####################################

HOSTS_FILE = "/etc/ansible/hosts"
SUCCEEDED = 0
FAILED = 1

## methods ######################################
def logs( message, fields={ } )
  if options[:logs]
    @logger ||= begin
      l = Logger.new(STDERR)
      l.level = Logger::INFO
      l
    end

    fields[:time] = Time.now.to_s
    fields[:message] = message
    @logger.info fields.to_json
  end
end

def options
  @__options__ ||= begin
    options = { }

    # define our options parser and flags we are explicitly
    # looking for
    parser = OptionParser.new do |opts|
      opts.on("--logs") do |v|
        options[:logs] = true
      end
      opts.on("--ini") do |v|
        options[:ini] = true
      end
    end.parse!

    # finally return options to caller
    options
  end
end

# host definitions are passed to plugin on stdin
def hosts
  @__hosts__ ||= begin
    JSON.parse STDIN.read
  end
end

def hostsfile
  ENV['HOSTS_FILE'] || HOSTS_FILE
end

def working_directory
  @__working_directory__ ||= begin
    "/tmp/.ansible-#{ Time.now.to_i }"
  end
end

def command cmd
  %x{ bash -c "#{ cmd }" }
end

def inventory
  @__inventory__ ||= begin
    content = File.read hostsfile

    # parse ;includes against content
    while content =~ /^;includes.+$/
      statement = ( content.match /^;includes.+$/ ).to_s
      logs "parsed includes statement", statement: statement

      includes = [ ]
      count = 0
      statement.scan /([^\s]+?)=([^\s]+)/ do | key, value |
        includes += hosts["tag_#{ key }_#{ value }"] || [ ]
        count += 1
        logs "matched hosts for tag", {
          statement: statement,
          tag: key,
          value: value,
          hosts: hosts["tag_#{ key }_#{ value }"]
        }
      end

      includes = ( includes.select { | value | includes.count( value ) >= count } ).uniq
      logs "matched hosts for include statement", statement: statement, hosts: includes

      includes = includes.map do | host |
        "host-#{ host } ansible_host=#{ host }"
      end

      content.sub! statement, includes.join( "\n" )
    end

    logs "finished parsing includes", content: content

    # we write content to tmp and pass to inventory-to-json
    unless options[:ini]
      logs "writing parsed hosts to working directory", directory: working_directory
      FileUtils::mkdir_p working_directory
      File.write path = "#{ working_directory }/hosts", content
      content = command "./bin/inventory-to-json #{ path }"
      FileUtils.rm_rf working_directory
      logs "converted parsed content to json", content: content
    end

    content
  end
end


## main #########################################

def main arguments
  logs "init"

  begin
    puts inventory
  rescue => e
    logs "failed determining inventory", error: e
    return FAILED
  end

  logs "succeeded"
  SUCCEEDED
end

exit main( ARGV )
