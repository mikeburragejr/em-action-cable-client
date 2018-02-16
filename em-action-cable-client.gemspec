# Author:: Mike Burrage Jr
# Copyright:: Copyright (c) 2018 Mike Burrage Jr
# frozen_string_literal: true
#--

Gem::Specification.new do |gem|
	gem.name = 'em-action-cable-client'
	gem.summary = 'ActionCable client (websockets) using EventMachine for ruby.'
	gem.authors = ['Mike Burrage Jr']
	gem.email = 'root@localhost' # Send yourself mail. Spammers.
	gem.has_rdoc = true
	gem.files = Dir.glob 'lib/**/*'
	gem.require_paths = %w(lib)
	gem.version = '0.1.0'
	gem.date = '2018-02-15'
	gem.required_ruby_version = '>= 2.3.0'
	gem.add_runtime_dependency 'websocket-eventmachine-client', '>= 1.2.0'
end
