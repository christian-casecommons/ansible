#!/usr/bin/env ruby
require "rake"
require "rspec/core/rake_task"

Dir.glob("lib/common/*.rb").each { | r | require_relative r }
Dir.glob("lib/tasks/*.rake").each { | r | import r }
