require 'rubygems'
require 'net/http'
require 'uri'
require 'json'
require 'colorize'
require 'faye/websocket'

Url = 'wss://stream.binance.com:9443/ws/iotxusdt@aggTrade'
# 資產
$asset = 0
# 付出的代價
$s_asset = 0
# 幣別
$currency = 28

up = '⬆'.colorize(:light_green)
down = '⬇'.colorize(:light_red)

$temp_price = 0
$open_price = 0

$high_price = 0
$deep_price = 0
$t_high_price = 0
$t_deep_price = 0

module Tools; end
class Tools::Telegram
  DOMAIN = 'https://api.telegram.org/'
  TOKEN = ''
  METHOD = 'sendMessage'
  CHAT = '@IoTeXAlert'
  class << self
    def send_message(message)
      uri = URI.parse("#{DOMAIN}bot#{TOKEN}/#{METHOD}?chat_id=#{CHAT}&text=#{message}")
      request = Net::HTTP::Get.new(uri)
      req_options = {
        use_ssl: uri.scheme == "https",
      }

      response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
        http.request(request)
      end
    end
  end
end

class Tools::Api
  DOMAIN = 'https://api.binance.com/'
  METHOD = 'api/v3/ticker/24hr?'
  CURRENCY = 'symbol=IOTXUSDT'
  class << self
    def get_24hr_ticker_price
      begin
        uri = URI.parse("#{DOMAIN}#{METHOD}#{CURRENCY}")
        request = Net::HTTP::Get.new(uri)
        req_options = {
          use_ssl: uri.scheme == "https",
        }

        response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
          http.request(request)
        end

        response = JSON.parse(response.body)

        $open_price = response["openPrice"].to_f
        $high_price = $asset * $currency * response["highPrice"].to_f
        $deep_price = $asset * $currency * response["lowPrice"].to_f
        $t_high_price = $asset * $currency * response["highPrice"].to_f
        $t_deep_price = $asset * $currency * response["lowPrice"].to_f
        Tools::Telegram::send_message("Today High: #{response["highPrice"]} / Today Low: #{response["lowPrice"]} / Today Opne: #{response["openPrice"]}")
      rescue => exception
        puts exception
      end
    end
  end
end

EM.run {
  ws = Faye::WebSocket::Client.new Url, [], tls: { ping: 15 }

  ws.on :open do |event|
    Tools::Telegram::send_message("Server Open")
    Tools::Api.get_24hr_ticker_price
  end

  ws.on :message do |msg|
    begin
      # puts msg
      data = JSON.parse msg.data.to_s

      $high_price = data.dig('p').to_f * $asset * $currency > $high_price ? data.dig('p').to_f * $asset * $currency : $high_price
      $deep_price = data.dig('p').to_f * $asset * $currency < $deep_price ? data.dig('p').to_f * $asset * $currency : $deep_price

      puts "#{data.dig('p')} - At: #{Time.now}".colorize(:light_blue) + "#{ $open_price > data.dig('p').to_f ? down : up}"
      puts "C: #{data.dig('p').to_f * $asset * $currency}#{ data.dig('p').to_f > $temp_price ? up : down} / S: #{data.dig('p').to_f * $asset * $currency - $s_asset}" + "#{ data.dig('p').to_f > $temp_price ? up : down} / H: #{$high_price} #{data.dig('p').to_f * $asset * $currency > $t_high_price ? 'ʕ•ᴥ•ʔ'.colorize(:light_green) : ''} / D: #{$deep_price} #{data.dig('p').to_f * $asset * $currency < $t_deep_price ? 'ʕ•ᴥ•ʔ'.colorize(:light_red) : ''}"

      if data.dig('p').to_f * $asset * $currency > $t_high_price
        Tools::Telegram::send_message("High / Current IoTeX Price: #{data.dig('p').to_f.to_s} / Asset: #{data.dig('p').to_f * $asset * $currency}")
      elsif data.dig('p').to_f * $asset * $currency < $t_deep_price
        Tools::Telegram::send_message("Down / Current IoTeX Price: #{data.dig('p').to_f.to_s} / Asset: #{data.dig('p').to_f * $asset * $currency}")
      end

      $t_high_price = $high_price
      $t_deep_price = $deep_price
      $temp_price = data.dig('p').to_f

    rescue => exception
      ws.ping "PING: #{exception.to_s}" do
        puts "PING: #{exception}".colorize(:red)
      end
      puts exception
    end
  end

  ws.on :close do |event|
    p [:close, event.code, event.reason]
    ws = nil
    Tools::Telegram::send_message("Server Close")
  end

  # loop do
  #   ws.send STDIN.gets.strip
  # end
}
