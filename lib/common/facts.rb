#!/usr/bin/env ruby
# Not alternative facts
require "json"

def facts
  $__facts__ ||= begin
    JSON.parse STDIN.read
  end
end
