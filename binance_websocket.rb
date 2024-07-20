require 'rubygems'
require 'active_support/all'
require 'net/http'
require 'uri'
require 'json'
require 'colorize'
require 'faye/websocket'
# wss://stream.binance.com:9443/ws/iotxusdt@kline_1m
# wss://fstream.binance.com/ws/iotxusdt@kline_1m
Url = 'wss://stream.binance.com:9443/ws/iotxusdt@aggTrade'
Url2 = 'wss://stream.binance.com:9443/ws/busdtwd@aggTrade'
# 資產
$asset = 0
# 付出的代價
# 幣別
$currency = 0
$current_ip = '127.0.0.1'
$currency_first_tag = false

$up = '⬆'.colorize(:light_green)
$down = '⬇'.colorize(:light_red)

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
        Thread.new { Tools::Telegram::send_message("Today High: #{response["highPrice"]} / Today Low: #{response["lowPrice"]} / Today Opne: #{response["openPrice"]}") }
      rescue => exception
        puts exception
      end
    end

    def calculate_rsi(average_prices, period = 14)
      gains = []
      losses = []

      # 计算平均价格的变化
      average_prices.each_cons(2) do |previous_price, current_price|
        change = current_price - previous_price
        if change > 0
          gains << change
          losses << 0
        else
          gains << 0
          losses << change.abs
        end
      end

      # 计算平均上升和下降
      avg_gain = gains.sum(0.0) / period
      avg_loss = losses.sum(0.0) / period

      # 避免除以零
      return 100 if avg_loss == 0

      # 计算 RSI
      rs = avg_gain / avg_loss
      rsi = 100 - (100 / (1 + rs))

      rsi
    end

    def get_usdt_to_twd_price
      begin
        uri = URI.parse("https://www.binance.com/bapi/asset/v1/public/asset-service/product/currency")
        request = Net::HTTP::Get.new(uri)
        req_options = {
          use_ssl: uri.scheme == "https",
        }

        response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
          http.request(request)
        end

        response = JSON.parse(response.body)
        old_price = $currency
        new_price = response['data'].find { |rate| rate["pair"] == "TWD_USD" }&.dig("rate")

        $currency = response.blank? ? 32.5 : new_price
        if old_price != new_price || $currency_first_tag == false
          $currency_first_tag = true
          Thread.new { Tools::Telegram::send_message("Current USDT-TWD: #{$currency}") }
        end
      rescue => exception
        puts exception
      end
    end
  end
end

def detect_vpn_change
  uri = URI.parse("https://ipinfo.io")
  request = Net::HTTP::Get.new(uri)
  req_options = {
    use_ssl: uri.scheme == "https",
  }

  response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
    http.request(request)
  end

  response = JSON.parse(response.body)
  now_ip = response["ip"]
  if $current_ip == '127.0.0.1'
    $current_ip = now_ip
  elsif $current_ip != now_ip
    return true
  end

  false
end

def valid_json?(json)
  JSON.parse(json)
  true
rescue JSON::ParserError
  false
end

puts "SSL support: #{EM.ssl?}"

def create_websocket
  EM.run {
    ws = Faye::WebSocket::Client.new Url, [], tls: { ping: 15 }

    ws.on :open do |event|
      Tools::Telegram::send_message("Server Open")
      Tools::Api.get_24hr_ticker_price
      Tools::Api.get_usdt_to_twd_price

      EM.add_periodic_timer(3600) do
        Tools::Api.get_usdt_to_twd_price
      end
    end

    ws.on :message do |msg|
      begin
        if valid_json?(msg.data.to_s)
          # puts msg
          data = JSON.parse msg.data.to_s

          $high_price = data.dig('p').to_f * $asset * $currency > $high_price ? data.dig('p').to_f * $asset * $currency : $high_price
          $deep_price = data.dig('p').to_f * $asset * $currency < $deep_price ? data.dig('p').to_f * $asset * $currency : $deep_price

          puts "#{data.dig('p').to_f} - At: #{Time.now}".colorize(:light_blue) + "#{ $open_price > data.dig('p').to_f ? $down : $up} TWD: #{$currency}"
          puts "C: #{format('%.2f', (data.dig('p').to_f * $asset * $currency).round(2)).gsub(/(\d)(?=\d{3}+\.)/, '\1,')}/#{format('%.2f', (data.dig('p').to_f * $realtime_asset * $currency).round(2)).gsub(/(\d)(?=\d{3}+\.)/, '\1,')}#{ data.dig('p').to_f > $temp_price ? $up : $down} / S: #{format('%.2f', (data.dig('p').to_f * $asset * $currency - $s_asset).round(2)).gsub(/(\d)(?=\d{3}+\.)/, '\1,')}" + "#{ data.dig('p').to_f > $temp_price ? $up : $down} / H: #{format('%.2f', $high_price.round(2)).gsub(/(\d)(?=\d{3}+\.)/, '\1,')} #{data.dig('p').to_f * $asset * $currency > $t_high_price ? 'ʕ•ᴥ•ʔ'.colorize(:light_green) : ''} / D: #{format('%.2f', $deep_price.round(2)).gsub(/(\d)(?=\d{3}+\.)/, '\1,')} #{data.dig('p').to_f * $asset * $currency < $t_deep_price ? 'ʕ•ᴥ•ʔ'.colorize(:light_red) : ''}"

          if data.dig('p').to_f * $asset * $currency > $t_high_price
            Thread.new { Tools::Telegram::send_message("High / Current #{$currency} IoTeX Price: #{data.dig('p').to_f.to_s} / Asset: #{data.dig('p').to_f * $asset * $currency}") }
          elsif data.dig('p').to_f * $asset * $currency < $t_deep_price
            Thread.new { Tools::Telegram::send_message("Down / Current #{$currency} IoTeX Price: #{data.dig('p').to_f.to_s} / Asset: #{data.dig('p').to_f * $asset * $currency}") }
          end

          $t_high_price = $high_price
          $t_deep_price = $deep_price
          $temp_price = data.dig('p').to_f
        else
          Tools::Telegram::send_message("Valid Json Error Server Restart...")
          ws.close
          reconnect
        end
      rescue => exception
        # ws.ping "PING: #{exception.to_s}" do
        #   puts "PING: #{exception}".colorize(:red)
        # end
        puts '=-=-=-= exception =-=-=-='
        puts exception.message
      end
    end

    EM.add_periodic_timer(5) do
      if detect_vpn_change
        puts 'Reset IP'
        $current_ip = '127.0.0.1'
        puts 'VPN or IP changed, reconnecting...'
        ws.close
        reconnect
      end
    end

    ws.on :close do |event|
      p [:close, event.code, event.reason]
      Tools::Telegram::send_message("Server Close")
    end

    ws.on :error do |event|
      Tools::Telegram::send_message("Error Message: #{event.message}")
      reconnect
    end
  }
end

def reconnect
  puts "Reconnecting..."
  create_websocket
end

EM.run do
  create_websocket
end
