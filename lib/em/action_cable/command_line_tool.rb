# Author:: Mike Burrage Jr
# Copyright:: Copyright (c) 2018 Mike Burrage Jr
# frozen_string_literal: true
#--

module EventMachine
	module ActionCable
		class CommandLineTool # :nodoc:
			def process(argv)
				client = EventMachine::ActionCable::Client.new argv[0]
				client.on_disconnected do
					puts "#{client} disconnected."
					EM.stop
				end
				client.on_welcomed do
					puts "#{client} connected and welcomed."
					EM.stop
				end

				EM.run do
					client.connect
					EventMachine::Timer.new(5) do
						client.close
					end
				end
			end
		end
	end
end
