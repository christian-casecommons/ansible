require 'rake'
require 'rspec/core/rake_task'

## methods ######################################

def hosts
  @__hosts__ ||= begin
    ( File.read "./hosts" ).scan( /\[(.+?)\]/ ).flatten
  end
end

## main #########################################

task :spec    => 'spec:all'
task :default => :spec

namespace :spec do
  task :all => hosts.map {|h| 'spec:' + h.split('.')[0] }

  desc "Run serverspec against role"
  RSpec::Core::RakeTask.new(:server, "role") do |t, arguments|
    ENV['TARGET_HOST'] = arguments[:role]
    t.pattern = "spec/#{ arguments[:role] }/*_spec.rb"
  end
end
