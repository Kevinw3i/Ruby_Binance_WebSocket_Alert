require 'rubygems'
require 'json'
require 'colorize'
require 'faye/websocket'

Url = 'wss://stream.binance.com:9443/ws/iotxusdt@aggTrade'
asset = 0
s_asset = 0
currency = 28

up = '⬆'.colorize(:light_green)
down = '⬇'.colorize(:light_red)

$temp_price = 0

$high_price = 0
$deep_price = 0
$t_high_price = 0
$t_deep_price = 0

EM.run {
  ws = Faye::WebSocket::Client.new Url, [], tls: { ping: 15 }

  ws.on :open do |event|
    p [:open]
    # ws.send('Hello, world!')
    #   # ws.send('{
    #   "method": "SUBSCRIBE",
    #   "params": ["iotxusdt@aggTrade"],
    #   "id": 1
    # }')
  end

  ws.on :message do |msg|
    begin
      # puts msg
      data = JSON.parse msg.data.to_s

      if $deep_price == 0
        $high_price = $deep_price = data.dig('p').to_f * asset * currency
      else
        $high_price = data.dig('p').to_f * asset * currency > $high_price ? data.dig('p').to_f * asset * currency : $high_price
        $deep_price = data.dig('p').to_f * asset * currency < $deep_price ? data.dig('p').to_f * asset * currency : $deep_price
      end

      puts "#{data.dig('p')} - At: #{Time.now}".colorize(:light_blue)
      puts "C: #{data.dig('p').to_f * asset * currency}#{ data.dig('p').to_f > $temp_price ? up : down} / S: #{data.dig('p').to_f * asset * currency - s_asset}" + "#{ data.dig('p').to_f > $temp_price ? up : down} / H: #{$high_price} #{data.dig('p').to_f * asset * currency > $t_high_price ? 'ʕ•ᴥ•ʔ'.colorize(:light_green) : ''} / D: #{$deep_price} #{data.dig('p').to_f * asset * currency < $t_deep_price ? 'ʕ•ᴥ•ʔ'.colorize(:light_red) : ''}"

      $t_high_price = $high_price
      $t_deep_price = $deep_price
      $temp_price = data.dig('p').to_f

    rescue => exception
      ws.ping "PING: #{exception.to_s}" do
        puts "PING: #{exception}".colorize(:red)
      end
      # puts "#{exception}".colorize(:red)
      # puts "Exception: #{msg}".colorize(:red)
    end
  end

  ws.on :close do |event|
    p [:close, event.code, event.reason]
    ws = nil
  end

  # loop do
  #   ws.send STDIN.gets.strip
  # end
}
