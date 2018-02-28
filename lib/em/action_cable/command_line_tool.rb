# Author:: Mike Burrage Jr
# Copyright:: Copyright (c) 2018 Mike Burrage Jr
# frozen_string_literal: true
#--

require 'eventmachine'

module EventMachine
	module ActionCable
		module KeyboardHandler # :nodoc:
			def initialize(client = nil)
				@client = client
				@q = ''
			end

			def receive_data(keystrokes)
				@q += keystrokes
				if keystrokes.include?("\n")
					line = @q.chomp
					@q = ''
					if line.start_with?('sub ', 'subscribe ')
						m = /\Asub(scribe)? +(?<channel>.+)/.match line
						channel = m['channel']
						begin
							channel = JSON.parse(channel) if channel.start_with?('{')
							@client.subscribe_to_channel channel
						rescue StandardError
						end
					elsif line.start_with?('send ')
						m = /\Asend +(?<message>.+)/.match line
						msg = m['message']
						begin
							msg = JSON.parse(msg) if msg.start_with?('{')
							@client.send_message msg
						rescue StandardError
						end
					elsif ['close', 'disconnect'].include?(line)
						@client.close
					elsif ['connect', 'reconnect', 'open'].include?(line)
						@client.connect
					elsif ['exit', 'quit'].include?(line)
						EM.stop
					else # if ['help', '?'].include?(line)
						puts "Commands:\n\n"
						puts '  subscribe CHANNEL'
						puts '  close'
						puts '  open'
						puts '  exit'
						puts "  help\n\n"
					end

					print '> '
				end
			end
		end

		class CommandLineTool # :nodoc:
			def process(argv)
				@client = EventMachine::ActionCable::Client.new argv[0], reconnect: EventMachine::ActionCable::Reconnect.default
				@client.on_disconnected do
					puts "#{@client} disconnected."
				end
				@client.on_subscribed do |channel|
					puts "#{@client} subscribed to #{channel}."
				end
				@client.on_welcomed do
					puts "#{@client} connected and welcomed."
				end

				EM.run do
					@client.connect
					print '> '
					EM.open_keyboard KeyboardHandler, @client
				end
			end
		end
	end
end
