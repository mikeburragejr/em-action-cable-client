# Author:: Mike Burrage Jr
# Copyright:: Copyright (c) 2018 Mike Burrage Jr
# frozen_string_literal: true
#--
require 'simplecov'
require 'simplecov-rcov'

SimpleCov.formatters = [SimpleCov::Formatter::HTMLFormatter, SimpleCov::Formatter::RcovFormatter]
SimpleCov.start do
	coverage_dir 'output/coverage'
	add_filter '/test/'
	add_group 'Libraries', '/lib/em/action_cable/'
end

Dir[File.expand_path('../../lib/em/action_cable/*.rb', __FILE__)].each { |file| require file}
require 'minitest/autorun'
