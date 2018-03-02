# Author:: Mike Burrage Jr
# Copyright:: Copyright (c) 2018 Mike Burrage Jr
# frozen_string_literal: true
#--

require 'docopt'
require 'eventmachine'

module EventMachine # :nodoc:
	module ActionCable # :nodoc:
		class Cli # :nodoc:
			PROMPT = '> '

			def display_prompt
				print PROMPT
				return self
			end

			def process_command(line)
				if line.start_with?('sub ', 'subscribe ')
					m = /\Asub(scribe)? +(?<channel>.+)/.match line
					channel = m['channel']
					begin
						channel = JSON.parse(channel) if channel.start_with?('{')
						@client.subscribe_to_channel channel
					rescue StandardError
						@client.subscribe_to_channel channel
					end
				elsif line.start_with?('send ')
					m = /\Asend +(?<message>.+)/.match line
					msg = m['message']
					begin
						msg = JSON.parse(msg) if msg.start_with?('{')
						@client.send_message msg
					rescue StandardError
						@client.send_message msg
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

				display_prompt
				return self
			end
		end

		module KeyboardHandler # :nodoc:
			def initialize(client = nil, cli = nil)
				@client = client
				@cli = cli
				@q = ''
				@cli.display_prompt
			end

			def current_line
				return @q
			end

			def receive_data(keystrokes)
				@q += keystrokes
				if keystrokes.include?("\n")
					line = @q.chomp
					@q = ''
					@cli.process_command line
				end
			end
		end

		class CommandLineTool # :nodoc:
			def process(argv)
				doc = <<DOCOPT
Usage:
    dead-kenny --version
    dead-kenny -h, --help
    dead-kenny [-v] <WEB_SOCKET_URI>

Options:
    --version        Display version and exit
    -v               Verbose
    -h, --help
    WEB_SOCKET_URI
DOCOPT

				begin
					options = Docopt.docopt doc, argv: argv
				rescue StandardError
					options = {help: true}
					is_bad = true
				end
				if options[:help]
					puts doc
					return is_bad ? 1 : 0
				elsif options['--version']
					puts "dead-kenny #{ClientVersion::VERSION} #{ClientVersion::VERSION_DATE}"
					return 0
				end

				@cli = Cli.new
				@client = EventMachine::ActionCable::Client.new options['<WEB_SOCKET_URI>'],
					reconnect: EventMachine::ActionCable::Reconnect.default
				Client.logger.formatter = proc do |severity, datetime, progname, msg|
					"\n#{datetime} #{severity} -- #{progname} #{msg}"
				end
				if options['-v']
					Client.logger.level = ::Logger::DEBUG
				end
				@client.on_connected do
					puts "\n#{@client} connected."
					@cli.display_prompt
				end
				@client.on_connect_failed do
					puts "\n#{@client} failed to connect."
					@cli.display_prompt
				end
				@client.on_disconnected do
					puts "\n#{@client} disconnected."
					@cli.display_prompt
				end
				@client.on_subscribed do |channel|
					puts "\n#{@client} subscribed to #{channel}."
					@cli.display_prompt
				end
				@client.on_welcomed do
					puts "\n#{@client} connected and welcomed."
					@cli.display_prompt
				end

				EM.run do
					@client.connect
					EM.open_keyboard KeyboardHandler, @client, @cli
				end
			end
		end
	end
end
