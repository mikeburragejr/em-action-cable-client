# Author:: Mike Burrage Jr
# Copyright:: Copyright (c) 2018 Mike Burrage Jr
# frozen_string_literal: true
#--
require 'logger'
require 'json'
require 'set'
require 'uri'
require 'websocket-eventmachine-client'

module EventMachine
	# Robust EventMachine-based ActionCable client.
	module ActionCable
		# ActionCable client using EventMachine sockets. ActionCable is a WebSocket wrapper protocol used in Rails and
		# adding a bit more structure around message passing, providing multiplexing (use of channels) and utilizing
		# keep-alive messages.
		# State machine is simplified and will get confused in some edge cases around
		# subscribing/unsubscribing/closing/reconnecting in rapid succession. So don't subscribe while closing...
		class Client
			module Command
				CONFIRM_SUBSCRIPTION = 'confirm_subscription'
				MESSAGE = 'message'
				PING = 'ping'
				SUBSCRIBE = 'subscribe'
				UNSUBSCRIBE = 'unsubscribe'
				WELCOME = 'welcome'
			end

			module ConnectionState
				DISCONNECTED = 0
				CONNECTING = 1
				CONNECTED = 2
				WELCOMED = 3
				DISCONNECTING = 4
			end

			module SubscriptionState
				UNSUBSCRIBED = 0
				SUBSCRIBING = 1
				SUBSCRIBED = 2
				UNSUBSCRIBING = 3
			end

			# Assuming *authority* (host at least) is provided after this.
			URL_SCHEME_REGEX = %r{\A(?<scheme>[a-z][a-z0-9+\-.]*)://}i
			SECURE_URL_SCHEMES = Set['ftps', 'https', 'hxxps', 'rtsps', 'sftp', 'wss'].freeze
			HTTP_SCHEMES = Set['https', 'http'].freeze
			WEBSOCKET_SCHEMES = Set['wss', 'ws'].freeze

			# @!group Class members
			@logger = ::Logger.new STDOUT
			@logger.level = ::Logger::ERROR

			class << self
				attr_accessor :logger
			end

			# Convert provided URL to ws/wss protocol.
			def self.normalize_websocket_url(url)
				url_match = URL_SCHEME_REGEX.match url
				if url_match.nil? # ASSUMPTION: Not fully qualified.
					url = 'ws://' + url
				else
					scheme = url_match[1].downcase
					if HTTP_SCHEMES.include?(scheme)
						url = 'ws' + url[4..-1]
					elsif !WEBSOCKET_SCHEMES.include?(scheme)
						url = 'ws' + url[scheme.length..-1]
					end
				end
				return url
			end

			# Initialize a connection, but don't connect.
			# @param [String] uri URI to connect client to.
			# @param [Hash] http_headers HTTP headers to supply during connection attempts. If nil, 'origin' will be defaulted
			#   based on the uri.
			# @param [Reconnect?] reconnect Reconnection algorithm.
			# @param [Number?] welcome_timeout Timeout in seconds between attempted connects and welcome being received
			# @return [Client] self
			def initialize(uri, http_headers: nil, reconnect: nil, welcome_timeout: nil)
				@_channels = [] # id, txt (version of the identifier), state
				@_connection = nil
				@_explicit_close = false
				@_http_headers = http_headers
				@_on_connected_block = nil
				@_on_connect_failed_block = nil
				@_on_custom_message_received_block = nil
				@_on_disconnected_block = nil
				@_on_pinged_block = nil
				@_on_subscribed_block = nil
				@_on_subscribed_block = nil
				@_on_welcomed_block = nil
				@_reconnect = reconnect
				@_reconnect.client = self if !@_reconnect.nil?
				@_uri = self.class.normalize_websocket_url uri
				@_state = ConnectionState::DISCONNECTED
				@_state_timer = nil
				@_welcome_timeout = welcome_timeout

				u = URI.parse @_uri
				if @_http_headers.nil?
					# Assumptions about origin in the default case (if it's using secure stuff, assume secure ws).
					is_secure = SECURE_URL_SCHEMES.include? u.scheme.downcase
					if is_secure
						port_part = (u.port.nil? || (443 == u.port)) ? '' : ":#{u.port}"
					else
						port_part = (u.port.nil? || (80 == u.port)) ? '' : ":#{u.port}"
					end
					origin = "#{(is_secure ? 'https' : 'http')}://#{u.host}#{port_part}"
					@_http_headers = {origin: origin}
				end
			end

			def channel_state(channel)
				channel_key = make_channel_key channel
				return nil if channel_key.nil?
				ch = @_channels.find { |el| (el[:id] == channel_key)}
				return ch&.dig(:state)
			end

			def close
				if ![ConnectionState::DISCONNECTING, ConnectionState::DISCONNECTED].include?(@_connection)
					@_explicit_close = true
					@_state = ConnectionState::DISCONNECTING
					@_connection.close
				end
				return self
			end

			def connected?
				return [ConnectionState::CONNECTED, ConnectionState::WELCOMED].include?(@_state)
			end

			# Connect to the server and proceed with automatic subscription to all channels, after the welcome.
			# May be called only while the EventMachine/reactor run loop is running (EM::reactor_running? == true).
			# @return [Client] self
			def connect
				if @_connection.nil? || [ConnectionState::DISCONNECTING, ConnectionState::DISCONNECTED].include?(@_state)
					# Somewhere down the chain 'headers' is being modified in place apparently (bug?), so dup it.
					@_state = ConnectionState::CONNECTING
					start_welcome_timer @_welcome_timeout

					@_connection = WebSocket::EventMachine::Client.connect(uri: @_uri, headers: @_http_headers&.dup)

					@_connection.onopen do
						logger.debug "#{self} opened."
						transition_state ConnectionState::CONNECTED, @_on_connected_block, :on_open
					end

					@_connection.onclose do
						f2c = [ConnectionState::CONNECTING, ConnectionState::CONNECTED].include? @_state
						logger.debug "#{self} #{f2c ? 'failed to connect' : 'closed'}."
						@_channels.each { |channel| channel[:state] = SubscriptionState::UNSUBSCRIBED}
						rm = !@_explicit_close ? :on_close : nil
						@_explicit_close = false
						transition_state ConnectionState::DISCONNECTED, f2c ? @_on_connect_failed_block : @_on_disconnected_block,
							rm
					end

					@_connection.onerror do
						f2c = [ConnectionState::CONNECTING, ConnectionState::CONNECTED].include? @_state
						logger.debug "#{self} #{f2c ? 'failed to connect' : 'closed (error)'}."
						@_channels.each { |channel| channel[:state] = SubscriptionState::UNSUBSCRIBED}
						rm = !@_explicit_close ? :on_close : nil
						@_explicit_close = false
						transition_state ConnectionState::DISCONNECTED, f2c ? @_on_connect_failed_block : @_on_disconnected_block,
							rm
					end

					@_connection.onmessage { |message, _type| on_received message}
				else
					logger.debug "#{self} connect() ignored in current state #{@_state}."
				end
				return self
			end

			def fully_connected_and_subscribed?
				return ConnectionState::WELCOMED.include?(@_state) &&
						!@_channels.any? { |ch| ch[:state] != SubscriptionState::SUBSCRIBED}
			end

			# Provide callback for when TCP/SSL connection is completed.
			def on_connected(&block)
				@_on_connected_block = block
			end

			def on_connect_failed(&block)
				@_on_connect_failed_block = block
			end

			# Provide callback for when messages are received other than 'ping', 'welcome', and 'confirm_subscription'.
			# block(message) is called. *message* is a hash if JSON decoded properly, otherwise string.
			def on_custom_message_received(&block)
				@_on_custom_message_received_block = block
			end

			# Provide callback for when TCP/SSL connection (socket) is closed.
			def on_disconnected(&block)
				@_on_disconnected_block = block
			end

			# Provide callback for when 'ping' message is received.
			# block(message) is called. *message* is a hash.
			def on_pinged(&block)
				@_on_pinged_block = block
			end

			# Provide callback for when 'confirm_subscription' message is received.
			# block(identifier) is called. *identifier* is a hash (the subscription identifier).
			def on_subscribed(&block)
				@_on_subscribed_block = block
			end

			# Provide callback for when 'welcome' message is received.
			# block(message) is called. *message* is a hash.
			def on_welcomed(&block)
				@_on_welcomed_block = block
			end

			def logger
				return EventMachine::ActionCable::Client.logger
			end

			# This DOES NOT queue messages.
			# Message should likely include 'action' attribute.
			# @param [Hash] message Object sent to the ActionCable server. This should include 'action' attribute which is the
			#   METHOD called on the server-side channel.
			# @param [Hash or String] channel
			# @return [Integer] Number of messages sent (0 if no channels in the SUBSCRIBED state).
			def send_message(message, channel: nil)
				messages_sent = 0
				channel_key = make_channel_key channel
				@_channels.each do |ch|
					if (channel_key.nil? || (ch[:id] == channel_key)) && (SubscriptionState::SUBSCRIBED == ch[:state])
						messages_sent += 1
						@_connection.send({command: Command::MESSAGE, identifier: ch[:txt], data: message.to_json}.to_json)
					end
				end
				logger.debug "#{self} send_message() ignored. No matching subscribed channel (#{channel_key})." \
 					if messages_sent.zero?

				return messages_sent
			end

			def state
				return @_state
			end

			# Subscribe to a channel (or indicate the desire to do so when the connection is established).
			# A string can be used (ie 'TestChannel') or a Hash can be provided (ie { channel: 'TestChannel', myid: 123 }).
			# If not in a WELCOMED state, this is a channel that will be subscribed to once welcomed.
			# @param [String or Hash] channel Channel name, or hash containing 'channel' attribute and other keys that will
			#   be added to the subscription request (and all other requests on the channel). Eg - { channel: 'ChatChannel',
			#   id: 'Bob' }
			# @return [Hash] identifier for the channel
			def subscribe_to_channel(channel)
				channel_key = make_channel_key channel
				if !@_channels.any? { |ch| ch[:id] == channel_key}
					rec = {id: channel_key, state: SubscriptionState::UNSUBSCRIBED, txt: channel_key.to_json}
					@_channels << rec
					if ConnectionState::WELCOMED == @_state
						rec[:state] = SubscriptionState::SUBSCRIBING
						@_connection.send({command: Command::SUBSCRIBE, identifier: rec[:txt]}.to_json)
					end
				else
					channel_key = @_channels.find { |ch| ch[:id] == channel_key}
					logger.debug "#{self} subscribe_to_channel() ignored. Duplicate subscription to channel (#{channel_key})."
				end

				return channel_key.dup
			end

			def to_s
				return "EventMachine::ActionCable::Client(#{@_uri})"
			end

			def unsubscribe_from_channel(channel)
				channel = make_channel_key channel
				@_channels.each do |ch|
					if (ch[:id] == channel) &&
							[SubscriptionState::SUBSCRIBING, SubscriptionState::SUBSCRIBED].include?(ch[:state])
						@_connection.send({command: Command::UNSUBSCRIBE, identifier: ch[:txt]}.to_json)
					end
				end
				@_channels.delete_if { |ch| ch[:id] == channel}
				return self
			end

			def welcome_timeout
				return @_welcome_timeout
			end

			def welcome_timeout=(val)
				val = nil if !val.nil? && val <= 0
				if !val.nil?
					if !@_start_timer.nil? && (val != @_welcome_timeout)
						start_welcome_timer((val <= @_welcome_timeout) ? 0 : (@_welcome_timeout - val))
					end
					@_welcome_timeout = val
				else
					if !@_start_timer.nil?
						@_start_timer.cancel
						@_start_timer = nil
					end
					@_welcome_timeout = nil
				end
				return @_welcome_timeout
			end

			private

			# From user-specified (or network returned) channel identifying information - create a canonical form that can
			# be matched against @_channels->:id
			# @param [String or Hash] channel Channel name or identifying hash.
			# @return [Hash] Canonical identifier for the channel
			def make_channel_key(channel)
				return nil if channel.nil?
				if channel.is_a?(String)
					channel_key = {'channel' => channel}
				elsif channel.is_a?(Hash)
					channel_key = sort_hash(channel)
				else
					channel_key = channel.dup
				end
				return channel_key
			end

			def on_received(message)
				return if message.nil? || message.empty?

				logger.debug "#{self} received message #{message}."

				begin
					json = JSON.parse message
				rescue StandardError => e
					logger.error "#{self} Received MALFORMED message. #{e}. #{message}"
					!@_on_custom_message_received_block.nil? && @_on_custom_message_received_block.call(message)
					return
				end

				case json['type']
				when Command::CONFIRM_SUBSCRIPTION
					begin
						chid = JSON.parse json['identifier']
					rescue StandardError => e
						logger.error "#{self} Received MALFORMED confirm_subscription identifier. #{e}. #{json['identifier']}"
					end
					found = nil
					@_channels.each do |ch|
						if (ch[:id] == chid) && (SubscriptionState::SUBSCRIBING == ch[:state])
							logger.debug "#{self} subscription to #{chid} confirmed."
							ch[:state] = SubscriptionState::SUBSCRIBED
							found = chid
						end
						safe_callback @_on_subscribed_block, chid
					end
					logger.warn "#{self} received subscription confirmation #{chid} to unrecognized channel." if found.nil?

				when Command::PING
					safe_callback @_on_pinged_block, json

				when Command::WELCOME
					if ConnectionState::CONNECTED == @_state
						logger.debug "#{self} welcome received. Autosubscribing..."
						@_state = ConnectionState::WELCOMED
						if !@_state_timer.nil?
							@_state_timer.cancel
							@_state_timer = nil
						end
						@_channels.each do |channel|
							channel[:state] = SubscriptionState::SUBSCRIBING
							@_connection.send({command: Command::SUBSCRIBE, identifier: channel[:txt]}.to_json)
						end
					end
					safe_callback @_on_welcomed_block, json

				else
					logger.debug "#{self} custom message received. #{message}"
					safe_callback @_on_custom_message_received_block, json
				end
			end

			def safe_callback(callback, *args)
				begin
					!callback.nil? && callback.call(*args)
				rescue StandardError => e
					logger.error "#{self} callback exception. #{e.message}\n#{e.backtrace}"
				end
				return self
			end

			def sort_hash(h)
				{}.tap do |h2|
					h.sort.each do |k, v|
						h2[k.to_s] = v.is_a?(Hash) ? sort_hash(v) : v
					end
				end
			end

			def start_welcome_timer(secs)
				@_state_timer.cancel if !@state_timer.nil?
				if !secs.nil?
					@_state_timer = EventMachine::Timer.new(secs) {@_connection.close}
				end
				return self
			end

			def transition_state(new_state, callback, reconnect_method)
				case new_state
				when ConnectionState::DISCONNECTED
					if !@_state_timer.nil?
						@_state_timer.cancel
						@_state_timer = nil
					end
				end
				@_state = new_state
				safe_callback callback
				@_reconnect.send(reconnect_method) if !@_reconnect.nil? && !reconnect_method.nil?
				return self
			end
		end
	end
end
