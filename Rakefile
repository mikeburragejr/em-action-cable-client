# Author:: Mike Burrage Jr
# Copyright:: Copyright (c) 2018 Mike Burrage Jr
# frozen_string_literal: true
#--
require 'bundler/gem_tasks'
Bundler::GemHelper.install_tasks
require 'rake/testtask'
require 'yard'
require 'yard/rake/yardoc_task'
require 'rubocop/rake_task'
require 'ci/reporter/rake/minitest'

root_dir = File.expand_path '..', __FILE__
doc_dir = File.expand_path 'output/doc/', root_dir
output_dir = File.expand_path 'output/', root_dir

tasks = Rake.application.instance_variable_get '@tasks'
tasks.each do |task|
	task[0] =~ /^default$/ && tasks.delete(task[0])
end

## Test

Rake::TestTask.new do |task|
	task.pattern = 'test/unit/**/*_test.rb'
	task.warning = false
end

ENV['CI_REPORTS'].nil? && ENV['CI_REPORTS'] = File.expand_path('output/test', root_dir)
coverage_dir = File.expand_path('../coverage', ENV['CI_REPORTS'])

namespace :ci do
	task all: [] do
		Rake::Task['ci:setup:minitest'].invoke
		Rake::Task['test'].invoke
	end

	task clobber: nil do
		rm_rf ENV['CI_REPORTS']
		rm_rf coverage_dir
	end
end

task clobber: ['ci:clobber']

## Rubocop

RuboCop::RakeTask.new

## Doc

YARD::Rake::YardocTask.new do |t|
	t.files = ['lib/**/*.rb']
	t.options = ['--output-dir', doc_dir]
end

namespace :doc do
	task all: ['yard']

	task clobber: nil do
		rm_rf doc_dir, verbose: false
	end
end

task doc: ['doc:all']

task clean: nil do
	['output', 'pkg'].each { |d| rm_rf d}
end

task clobber: ['doc:clobber'] do
	rm_rf output_dir
end

task default: ['ci:all']

task full: ['ci:all', 'rubocop', 'doc:all']
