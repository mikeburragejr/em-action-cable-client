# Author:: Mike Burrage Jr
# Copyright:: Copyright (c) 2018 Mike Burrage Jr
# frozen_string_literal: true
#--

source 'https://rubygems.org'
fail 'Ruby should be >= 2.3' unless RUBY_VERSION.to_f >= 2.3

gem 'bundler', '>= 1.14.0', group: [:development, :test]
gem 'ci_reporter', '>= 2.0.0', group: [:development, :test]
gem 'ci_reporter_minitest', '>= 1.0.0', group: [:development, :test]
gem 'docopt', '>= 0.6.0'
gem 'rake', '>= 12.0', group: [:development, :test]

# I'm done upgrading rubocop ever. Every single fucking update adds work.
gem 'rubocop', '0.57.2', group: [:development, :test]

gem 'simplecov-rcov', '>= 0.2.3', group: [:development, :test]
gem 'websocket-eventmachine-client', '1.2.0', git: 'https://github.com/imanel/websocket-eventmachine-client.git',
	ref: '1ab5dd6'
gem 'yard', '>= 0.6', group: [:development, :test]
