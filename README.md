# em-action-cable-client

[![Build Status](https://travis-ci.org/mikeburragejr/em-action-cable-client.svg?branch=master)](https://travis-ci.org/mikeburragejr/em-action-cable-client)

This is a Ruby ActionCable/Websocket client library utilizing the
[EventMachine](https://github.com/eventmachine/eventmachine) framework (asynchronous) that handles:
* Default functionality supporting common RoR defaults (origin header, automatic subscription).
* Multiple channel subscription and bi-directional messaging.
* Interruptible and reconnection (that works).
* Automatic subscription to multiple channels.
* Connection and channels can be setup (for later auto-subscription) BEFORE the EventMachine run loop
is started.

## See also

[ActionCable](http://guides.rubyonrails.org/action_cable_overview.html) - Rails wrapper/extension to WebSockets
that includes multiplexed pub/sub.

[WebSockets](https://en.wikipedia.org/wiki/WebSocket) - bidirectional communication over HTTP.

[EventMachine](https://github.com/eventmachine/eventmachine) - async library for ruby.

## Example

```ruby

require 'em-action-cable-client'

ac_client = EventMachine::ActionCable::Client.new 'ws://127.0.0.1:6060/ac-server',
	http_headers: {origin: 'http://localhost:6060'}
channel_key = ac_client.subscribe_to_channel 'ActionCableClientChannel'
ac_client.on_subscribed do
	ac_client.send_message({action: 'status', status: "I'm fine. Thanks!"})
end

EM.run do
	ac_client.connect
end

```

## TODO

* Channel timeouts when subscription fails
* Unsubscribed callback
