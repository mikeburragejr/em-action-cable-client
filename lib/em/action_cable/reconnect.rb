# Author:: Mike Burrage Jr
# Copyright:: Copyright (c) 2018 Mike Burrage Jr
# frozen_string_literal: true
#--

module EventMachine
	module ActionCable
		# Factory for reconnection algorithms.
		class Reconnect
			def self.default
				return self.incremental_backoff
			end

			def self.incremental_backoff(initial_min: nil, initial_max: nil, max: nil)
				return EventMachine::ActionCable::IncrementalBackoffReconnect.new(initial_min: initial_min,
						initial_max: initial_max, max: max)
			end

			def on_close
			end

			def on_open
			end
		end
	end
end
