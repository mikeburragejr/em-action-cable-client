# Author:: Mike Burrage Jr
# Copyright:: Copyright (c) 2018 Mike Burrage Jr
# frozen_string_literal: true
#--

require_relative './lib/em/action_cable/client_version.rb'

Gem::Specification.new do |gem|
	gem.name = 'em-action-cable-client'
	gem.summary = 'ActionCable client (WebSockets) using EventMachine for ruby.'
	gem.authors = ['Mike Burrage Jr']
	gem.email = 'root@localhost' # Send yourself mail. Spammers.
	gem.has_rdoc = true
	gem.files = Dir.glob ['lib/**/*', 'bin/*']
	gem.test_files = Dir.glob 'test/**/*'
	gem.executables = 'dead-kenny'
	gem.require_paths = %w(lib)
	gem.version = EventMachine::ActionCable::ClientVersion::VERSION
	gem.date = EventMachine::ActionCable::ClientVersion::VERSION_DATE
	gem.required_ruby_version = '>= 2.3.0'
	gem.add_runtime_dependency 'docopt', '>= 0.6.0'
	gem.add_runtime_dependency 'websocket-eventmachine-client', '>= 1.2.0'
end
