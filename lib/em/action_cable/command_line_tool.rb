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

			def initialize(client)
				@client = client
			end

			def display_prompt
				print PROMPT
				return self
			end

			def process_command(line)
				if (m = /\Asub(scribe)? +(?<channel>.+)/.match(line))
					channel = m['channel']
					begin
						channel = JSON.parse(channel) if channel.start_with?('{')
					rescue StandardError
					end
					@client.subscribe_to_channel channel
				elsif (m = /\Achannel-state *(?<channel>.+)?/.match(line))
					channel = m['channel']
					begin
						channel = JSON.parse(channel) if channel.start_with?('{')
					rescue StandardError
					end
					cs = @client.channel_state channel
					puts cs.nil? ? 'Channel not found.' : "Channel(#{channel}) state: #{cs}."
				elsif (m = /\Asend +(?<message>.+)/.match(line))
					msg = m['message']
					begin
						msg = JSON.parse(msg) if msg.start_with?('{')
					rescue StandardError
					end
					@client.send_message msg
				elsif (m = /\Awelcome-timeout *(?<val>.+)?/.match(line))
					val = m['val']
					if val.nil?
						wts = @client.welcome_timeout.nil? ? 'NONE' : (@client.welcome_timeout.to_s + 'seconds')
						puts "Welcome timeout: #{wts}."
					else
						@client.welcome_timeout = val.to_f
					end
				elsif ['close', 'disconnect'].include?(line)
					@client.close
				elsif ['state', 'get-state'].include?(line)
					puts "Connection state: #{@client.state}"
				elsif ['connect', 'reconnect', 'open'].include?(line)
					@client.connect
				elsif ['exit', 'quit', 'bye', 'adios', '\q'].include?(line)
					EM.stop
				elsif !line.empty? # if ['help', '?'].include?(line)
					puts "Commands:\n\n"
					puts '  sub(scribe) CHANNEL'
					puts '  send MESSAGE'
					puts '  channel-state CHANNEL'
					puts '  close'
					puts '  open'
					puts '  exit'
					puts '  welcome-timeout VAL'
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
					puts "\nOH MY GOD! THEY KILLED KENNY!\nYOU BASTARDS\n"
					return 0
				end

				@client = EventMachine::ActionCable::Client.new options['<WEB_SOCKET_URI>'],
					reconnect: EventMachine::ActionCable::Reconnect.default
				@cli = Cli.new @client
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
