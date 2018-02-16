# Author:: Mike Burrage Jr
# Copyright:: Copyright (c) 2018 Mike Burrage Jr
# frozen_string_literal: true
#--
require_relative '../../../test_helper'

module EventMachine
	module ActionCable
		class ClientTest < MiniTest::Test
			def test_connect_with_only_uri
				sc = MiniTest::Mock.new # Connection (instance)
				sc.expect :onclose, nil
				sc.expect :onerror, nil
				sc.expect :onopen, nil
				sc.expect :onmessage, nil

				stubbed_ws = WebSocket::EventMachine::Client
				wrapped_connect = lambda do |args|
					assert_equal({uri: 'ws://localhost:16616/ws-ac-client-test', headers: {origin: 'http://localhost:16616'}},
						args)
					sc
				end
				stubbed_ws.stub :connect, wrapped_connect do
					cut = EventMachine::ActionCable::Client.new 'ws://localhost:16616/ws-ac-client-test'
					cut.connect
				end
				assert_mock sc
				assert sc.verify
			end
		end
	end
end
