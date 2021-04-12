# encoding: utf-8

require 'mastodon'
require 'websocket-client-simple'
require 'json'
require_relative 'model.rb'
require_relative 'nlp.rb'

$instance_url = ""
$wss_url = $instance_url.gsub("https://", "wss://").gsub("http://", "wss://")
$bearer_token = ""
$corpus_path = ""
$bot_username = ""
$seen_status ||= {}
$api = nil
$model = nil
$mentions_counter = Hash.new
$mentions_counter_timer = Hash.new

def log(*args)
  STDOUT.print "@#{$bot_username}: " + args.map(&:to_s).join(' ') + "\n"
  STDOUT.flush
end

def handle_stream(ws)
  ws.on :open do
    log "Stream online!"
  end

  ws.on :close do
    log "Stream closed!"
    exit 1
  end

  ws.on :error do |e|
    log "Error in stream!"
    log e
  end

  ws.on :message do |msg|
    if msg.data.size > 0
      begin
        toot = JSON.parse(msg.data)
        handle_toot(toot)
      rescue => e
        log "Content parse error."
        log e
      end
    end
  end
end

def handle_toot(toot)
  if toot["event"] == "notification"
    body = JSON.parse(toot["payload"])

    if body["type"] == "mention"
      account = body["account"]["acct"]
      status_id = body["status"]["id"]
      is_reblog = !body['reblog'].nil?
      mentions = body["status"]["mentions"]

      # Ignore our own status
      return if account.downcase == $bot_username.downcase

      if is_reblog && $bot_username.downcase == body["reblog"]["account"]["acct"].downcase
        # Someone reblogged our status
        return
      end

      # Avoid responding to duplicate status
      if $seen_status[status_id]
        log "Not firing event for duplicate status #{status_id}"
        return
      else
        $seen_status[status_id] = true
      end

      mentions_bot = false
      mentions.each do |m|
        acct = m['acct']
        if acct.downcase == $bot_username.downcase
          mentions_bot = true
          break
        end
      end

      if !is_reblog && mentions_bot
        extra_mentions = get_extra_mentions(mentions)

        # Remove extra mentions to not spam people after being in the same mention chain 5 times
        if extra_mentions != ""
            sorted_mentions = get_mentions_sorted(mentions, account) 
            if !$mentions_counter[sorted_mentions].nil?
                # Reset after 15 minutes
                if (Process.clock_gettime(Process::CLOCK_MONOTONIC)-$mentions_counter_timer[sorted_mentions]) >= 900
                    $mentions_counter[sorted_mentions] = 1
                    $mentions_counter_timer[sorted_mentions] = Process.clock_gettime(Process::CLOCK_MONOTONIC)
                else if $mentions_counter[sorted_mentions] == 5
                    extra_mentions = ""
                else
                    $mentions_counter[sorted_mentions] = $mentions_counter[sorted_mentions]+1
                end
            else
                $mentions_counter[sorted_mentions] = 1
                $mentions_counter_timer[sorted_mentions] = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            end
        end

        status_text = NLP.remove_html_tags(body["status"]["content"])
        log "Mention from $#{account}: #{status_text}"
        resp = generate_reply(status_text)

        if extra_mentions != ""
            resp = "@#{account} #{extra_mentions} #{resp}"
        else
            resp = "@#{account} #{resp}"
        end

        log "Replying with: #{resp}"
        $api.create_status(resp, { in_reply_to_id: status_id })
      else
        # Timeline event
      end
    end
  end
end

def get_extra_mentions(mentions)
  extra_mentions = ""

  mentions.each do |m|
    next if m['acct'].downcase == $bot_username.downcase
    extra_mentions = extra_mentions + "@" + m['acct'] + " "
  end

  extra_mentions.strip
end

def get_mentions_sorted(mentions, account)
  sorted_mentions = ""
  menchies = []
  menchies.push(account)

  mentions.each do |m|
    next if m['acct'].downcase == $bot_username.downcase
    menchies.push(m['acct'])
  end

  menchies.sort!
  menchies.each do |m|
    sorted_mentions = sorted_mentions + "@" + m + " "
  end

  sorted_mentions.strip
end

def generate_reply(status_text, limit = 140)
  $model.make_response(status_text, limit)
end

def start()
  model_path = $corpus_path.split(".")[0] + ".model"

  if !File.file?(model_path)
    Model.consume($corpus_path).save(model_path)
  end

  log "Loading model #{model_path}"
  $model = Model.load(model_path)

  $api ||= Mastodon::REST::Client.new(base_url: $instance_url, bearer_token: $bearer_token)
  $bot_username = $api.verify_credentials.acct

  WebSocket::Client::Simple.connect("#{$wss_url}/api/v1/streaming?access_token=#{$bearer_token}&stream=user") do |ws|
    handle_stream(ws)
  end
end

start()

while true
end




