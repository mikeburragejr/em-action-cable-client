# Author:: Mike Burrage Jr
# Copyright:: Copyright (c) 2018 Mike Burrage Jr
# frozen_string_literal: true
#--
require 'logger'
require 'json'
require 'uri'
require 'websocket-eventmachine-client'

module EventMachine
	# Robust EventMachine-based ActionCable client.
	module ActionCable
		@logger = ::Logger.new STDOUT
		@logger.level = ::Logger::ERROR

		def self.logger
			return @logger
		end

		def self.logger=(logger)
			@logger = logger
		end

		# ActionCable client using EventMachine sockets. ActionCable is a WebSocket wrapper protocol used in Rails and
		# adding a bit more structure around message passing, providing multiplexing (use of channels) and utilizing
		# keep-alive messages.
		# State machine is simplified and will get confused in some edge cases around
		# subscribing/unsubscribing/closing/reconnecting in rapid succession. So don't subscribe while closing...
		class Client
			# Initialize a connection, but don't connect.
			# ==== Parameters
			# * +uri+ _String_ URI to connect client to.
			# ==== Options
			# * +http_headers+ _Hash_ HTTP headers to supply during connection attempts. If nil, 'origin' will be defaulted
			# based on the uri.
			# ==== Returns
			# _Client_ self
			def initialize(uri, http_headers: nil)
				@_channels = [] # id, txt, state (unsubscribed, subscribing, subscribed, unsubscribing)
				@_connection = nil
				@_http_headers = http_headers
				@_on_custom_message_received_block = nil
				@_on_disconnected_block = nil
				@_on_pinged_block = nil
				@_on_subscribed_block = nil
				@_on_welcomed_block = nil
				@_uri = uri
				@_state = 'disconnected' # disconnected, connecting, connected, disconnecting

				if @_http_headers.nil?
					# Assumptions about origin in the default case.
					u = URI.parse uri
					is_secure = ('wss' == u.scheme) || ('https' == u.scheme)
					if is_secure
						port_part = (u.port.nil? || (443 == u.port)) ? '' : ":#{u.port}"
					else
						port_part = (u.port.nil? || (80 == u.port)) ? '' : ":#{u.port}"
					end
					origin = (is_secure ? 'https' : 'http') + '://' + u.host + port_part
					@_http_headers = {origin: origin}
				end
			end

			# Subscribe to a channel (or indicate the desire to do so when the connection is established).
			# A string can be used (ie 'TestChannel') or a Hash can be provided (ie {channel: 'TestChannel', myid: 123}).
			# ==== Parameters
			# * +channel+ _String_|_Hash_ Channel name, or hash containing 'channel' attribute and other keys that will
			# be added to the subscription request (and all other requests on the channel). Eg - {channel: 'ChatChannel',
			# id: 'Bob'}
			# ==== Returns
			# _Hash_ identifier for the channel
			def add_channel(channel)
				channel = make_channel_key channel
				rec = {id: channel, state: 'unsubscribed', txt: channel.to_json}
				@_channels << rec
				if 'connected' == @_state
					rec[:state] = 'subscribing'
					@_connection.send({command: 'subscribe', identifier: rec[:txt]}.to_json)
				end
				return channel.dup
			end

			def close
				!@_connection.nil? && @_connection.close
				return self
			end

			def connected?
				return 'connected' == @_state
			end

			# Connect to the server and proceed with automatic subscription to all channels, after the welcome.
			# ==== Returns
			# _Client_ self
			# ==== Restrictions
			# * May be called only while the EventMachine/reactor run loop is running (EM::reactor_running? == true).
			def connect
				if @_connection.nil? || ['disconnecting', 'disconnected'].include?(@_state)
					# Somewhere down the chain 'headers' is being modified in place apparently (bug?), so dup it.
					@_state = 'connecting'
					@_connection = WebSocket::EventMachine::Client.connect(uri: @_uri, headers: @_http_headers&.dup)
					@_connection.onopen do
						logger.debug "#{self} opened."
					end
					@_connection.onclose do
						logger.debug "#{self} #{@_state == 'connecting' ? 'failed to connect' : 'closed'}."
						@_state = 'disconnected'
						@_channels.each { |channel| channel[:state] = 'unsubscribed'}
						!@_on_disconnected_block.nil? && @_on_disconnected_block.call
					end
					@_connection.onerror do
						logger.debug "#{self} #{@_state == 'connecting' ? 'failed to connect' : 'closed (error)'}."
						@_state = 'disconnected'
						@_channels.each { |channel| channel[:state] = 'unsubscribed'}
						!@_on_disconnected_block.nil? && @_on_disconnected_block.call
					end
					@_connection.onmessage { |message, _type| on_received message}
				end
				return self
			end

			def on_custom_message_received(&block)
				@_on_custom_message_received_block = block
			end

			def on_disconnected(&block)
				@_on_disconnected_block = block
			end

			def on_pinged(&block)
				@_on_pinged_block = block
			end

			def on_subscribed(&block)
				@_on_subscribed_block = block
			end

			def on_welcomed(&block)
				@_on_welcomed_block = block
			end

			def logger
				return EventMachine::ActionCable.logger
			end

			def remove_channel(channel)
				channel = make_channel_key channel
				@_channels.each do |ch|
					if (ch[:id] == channel) && ['subscribing', 'subscribed'].include?(ch[:state])
						@_connection.send({command: 'unsubscribe', identifier: ch[:txt]}.to_json)
					end
				end
				@_channels.delete_if { |ch| ch[:id] == channel}
				return self
			end

			def send_message(message, channel: nil)
				messages_sent = 0
				channel = make_channel_key channel
				@_channels.each do |ch|
					if (channel.nil? || (ch[:id] == channel)) && ('subscribed' == ch[:state])
						messages_sent += 1
						@_connection.send({command: 'message', identifier: ch[:txt], data: message.to_json}.to_json)
					end
				end
				return messages_sent
			end

			def to_s
				return "EventMachine::ActionCable::Client(#{@_uri})"
			end

			private

			# From user-specified (or network returned) channel identifying information - create a canonical form that can
			# be matched against @_channels->:id
			# ==== Parameters
			# * +channel+ _String_|_Hash_ Channel name or identifying hash.
			# ==== Returns
			# _Hash_ Canonical identifier for the channel
			def make_channel_key(channel)
				return nil if channel.nil?
				channel_key = {}
				if channel.is_a?(String)
					channel_key['channel'] = channel
				else
					channel.each_key { |k| channel_key[k.to_s] = channel[k]}
				end
				return channel_key
			end

			def on_received(message)
				return if message.nil? || message.empty?
				json = JSON.parse message

				logger.debug "#{self} received message #{message}."
				case json['type']
				when 'confirm_subscription'
					chid = JSON.parse json['identifier']
					@_channels.each do |ch|
						if (ch[:id] == chid) && ('subscribing' == ch[:state])
							logger.debug "#{self} subscription to #{chid} confirmed."
							ch[:state] = 'subscribed'
							!@_on_subscribed_block.nil? && @_on_subscribed_block.call(chid)
						end
					end
				when 'ping'
					!@_on_pinged_block.nil? && @_on_pinged_block.call(json)
				when 'welcome'
					if 'connecting' == @_state
						logger.debug "#{self} welcome received. Autosubscribing..."
						@_state = 'connected'
						@_channels.each do |channel|
							channel[:state] = 'subscribing'
							@_connection.send({command: 'subscribe', identifier: channel[:txt]}.to_json)
						end
					end
					!@_on_welcomed_block.nil? && @_on_welcomed_block.call(json)
				else
					logger.debug "#{self} custom message received. #{message}"
					!@_on_custom_message_received_block.nil? && @_on_custom_message_received_block.call(json)
				end
			end
		end
	end
end
