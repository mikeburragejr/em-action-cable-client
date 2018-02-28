# em-action-cable-client
[ActionCable](http://guides.rubyonrails.org/action_cable_overview.html) is a Rails wrapper around
[WebSockets](https://en.wikipedia.org/wiki/WebSocket) that includes multiplexing (channels/subscriptions).

This is a Ruby client library utilizing the [EventMachine](https://github.com/eventmachine/eventmachine) framework
(asynchronous) that handles:
* Default functionality supporting common RoR defaults (origin header, automatic subscription).
* Multiple channels.
* Interruptible and reconnection (that works).
* Automatic subscription to multiple channels.

## Example

```ruby

require 'em-action-cable-client'

ac_client = EventMachine::ActionCable::Client.new 'ws://127.0.0.1:6060/ac-server',
	http_headers: {origin: 'http://localhost:6060'}
channel1 = ac_client.subscribe_to_channel 'ActionCableClientChannel'
channel2 = ac_client.subscribe_to_channel channel: 'ChatClientChannel', name: 'Bob'
ac_client.on_subscribed do |chan|
	ac_client.send_message({action: 'alert', data: "Subscribed to channel #{chan}"})
	ac_client.send_message({action: 'send', message: 'Sup, Bob?'}, channel: channel2) if chan == channel2
end
ac_client.on_disconnected do
	EventMachine::Timer.new(5) do
		ac_client.connect
	end
end
EM.run do
	ac_client.connect
end

```

## TODO

* More timers/timeout control - connect-to-welcome timeout, subscribing-to-subscribed timeout
* Unsubscribed callback
* Connection and subscription state accessors
