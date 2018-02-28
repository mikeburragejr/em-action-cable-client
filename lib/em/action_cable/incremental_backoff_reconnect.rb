# Author:: Mike Burrage Jr
# Copyright:: Copyright (c) 2018 Mike Burrage Jr
# frozen_string_literal: true
#--

require_relative './reconnect.rb'

module EventMachine
	module ActionCable # :nodoc:
		# Reconnection algorithm that initially retries after a random amount of time and then incrementally increases
		# the delay for subsequent reconnects up to a max.
		class IncrementalBackoffReconnect < Reconnect
			DEFAULT_INITIAL_MIN = 0.5
			DEFAULT_INITIAL_MAX = 5
			DEFAULT_MAX = 5 * 60

			attr_accessor :client

			# intial_min
			def initialize(initial_min: nil, initial_max: nil, max: nil)
				@initial_min = initial_min
				@initial_min = DEFAULT_INITIAL_MIN if @initial_min.nil?
				@initial_min = 0 if @initial_min < 0
				@initial_max = initial_max
				@initial_max = DEFAULT_INITIAL_MAX if @initial_max.nil?
				@initial_max = @initial_min if @initial_max < @initial_min
				@max = max
				@max = DEFAULT_MAX if @max.nil?
				@max = @initial_max if @max < @initial_max
				@current = nil
				@timer = nil
			end

			def on_close
				@timer = EventMachine::Timer.new(new_current) do
					@client.logger.debug "#{client} reconnecting."
					@client.connect
				end
				return self
			end

			def on_open
				if !@timer.nil?
					@timer.cancel
					@timer = nil
					@current = nil
				end
				return self
			end

			private

			# Adjust the current timeout in seconds and return it.
			def new_current
				if @current.nil?
					@current = (@initial_min == @initial_max) ? @initial_min :
							@initial_min + Random.rand(@initial_max - @initial_min)
				else
					@current = @current.zero? ? 1 : (@current + @current)
					@current = @max if @current > @max
				end
				return @current
			end
		end
	end
end
