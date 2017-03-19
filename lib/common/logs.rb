#!/usr/bin/env ruby
require "logger"
require "json"

def logs( message, fields={ } )
  @logger ||= begin
    l = Logger.new(STDERR)
    l.level = Logger::INFO
    l
  end

  fields[:time] = Time.now.to_s
  fields[:message] = message
  @logger.info fields.to_json
end
