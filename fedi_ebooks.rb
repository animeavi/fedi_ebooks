# encoding: utf-8

require 'http/request'
require 'httparty'
require 'json'
require 'mastodon'
require 'rufus-scheduler'
require_relative 'model.rb'
require_relative 'nlp.rb'

$instance_url = ""
$bearer_token = ""
$corpus_path = [ "" ]
$bot_username = ""
$seen_status ||= {}
$api = nil
$model = nil
$software = 0
$mentions_counter = Hash.new
$mentions_counter_timer = Hash.new

class InstanceType
  TYPES = [
    MASTODON = 1,
    PLEROMA = 2,
    MISSKEY = 3
  ].freeze
end

scheduler = Rufus::Scheduler.new

def log(*args)
  STDOUT.print "@#{$bot_username}: " + args.map(&:to_s).join(' ') + "\n"
  STDOUT.flush
end

def reply()
  notifs = get_mentions_notifications()

  notifs.each do |n|
    account = n["account"]["acct"]
    status_id = n["status"]["id"]
    is_reblog = !n['reblog'].nil?
    mentions = n["status"]["mentions"]
    notif_id = n["id"]

    # Don't reply to other bots
    return if n["account"]["bot"]

    # Ignore our own status
    return if account.downcase == $bot_username.downcase

    if is_reblog && $bot_username.downcase == n["reblog"]["account"]["acct"].downcase
      # Someone reblogged our status
      return
    end

    # Avoid responding to duplicate status
    if $seen_status[status_id]
      log "Not handling duplicate status #{status_id}"
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
          elsif $mentions_counter[sorted_mentions] == 5
            extra_mentions = ""
          else
            $mentions_counter[sorted_mentions] = $mentions_counter[sorted_mentions]+1
          end
        else
          $mentions_counter[sorted_mentions] = 1
          $mentions_counter_timer[sorted_mentions] = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end

      status_text = NLP.remove_html_tags(n["status"]["content"])
      status_mentionless = get_status_mentionless(status_text, mentions)
      log "Mention from $#{account}: #{status_mentionless}"
      resp = generate_reply(status_mentionless)

      if extra_mentions != ""
        resp = "@#{account} #{extra_mentions} #{resp}"
      else
        resp = "@#{account} #{resp}"
      end

      log "Replying with: #{resp}"
      $api.create_status(resp, { in_reply_to_id: status_id })
      delete_notification(notif_id)
    else
      # Timeline event
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

def get_status_mentionless(status_text, mentions)
  mentions.each do |m|
    status_text = status_text.gsub('@' + m['acct'], '')
  end

  status_text.strip
end

def generate_reply(status_text, limit = 300)
  $model.make_response(status_text, limit)
end

def get_mentions_notifications()
  req_url = ""
  headers = { "Content-Type" => "application/json",
    "Authorization" => "Bearer #{$bearer_token}"}

  case $software
  when InstanceType::MASTODON
    req_url = $instance_url + "/api/v1/notifications" +
    "?exclude_types[]=follow&exclude_types[]=favourite&exclude_types[]=reblog" +
    "&exclude_types[]=poll&exclude_types[]=follow_request"
  when InstanceType::PLEROMA
    req_url = $instance_url + "/api/v1/notifications?include_types[]=mention"
  when InstanceType::MISSKEY
    log "Misskey support not implemented!"
    exit 1

    #body = { "i" => $bearer_token, "includeTypes" => [ "reply" ] }
    #headers = { "Content-Type" => "application/json" }
    #return JSON.parse(HTTParty.post($instance_url + "/api/i/notifications",
    #  :body => JSON.dump(body), :headers => headers).to_s)
    # NOTE: check if "isRead" is true
  else
    log "Invald instance type!"
    exit 1
  end

  JSON.parse(HTTParty.get(req_url, :headers => headers).to_s)
end

def delete_notification(id)
  req_url = ""
  headers = { "Authorization" => "Bearer #{$bearer_token}"}

  case $software
  when InstanceType::MASTODON
    req_url = $instance_url + "/api/v1/notifications/#{id}/dismiss"
    HTTParty.post(req_url, :headers => headers)
  when InstanceType::PLEROMA
    req_url = $instance_url + "/api/v1/notifications/destroy_multiple?ids[]=#{id}"
    HTTParty.delete(req_url, :headers => headers)
  when InstanceType::MISSKEY
    body = { "i" => $bearer_token, "notificationId" => id}
    HTTParty.post($instance_url + "/api/notifications/read", :body => JSON.dump(body))
  else
    log "Invald instance type!"
    exit 1
  end
end

def get_software()
  begin
    version = Mastodon::REST::Client.new(base_url: $instance_url).instance.version
    version = version.downcase

    if version.include? "pleroma"
      $software = InstanceType::PLEROMA
    else
      $software = InstanceType::MASTODON
    end

    return
  rescue
  end

  begin
    headers = { "Content-Type" => "application/json" }
    if !HTTParty.post($instance_url + "/api/meta",
      :headers => headers)['driveCapacityPerLocalUserMb'].nil?
      $software = InstanceType::MISSKEY

      return
    end
  rescue
  end
end

def init()
  get_software()
  if $software == InstanceType::MASTODON || $software == InstanceType::PLEROMA
    $api ||= Mastodon::REST::Client.new(base_url: $instance_url, bearer_token: $bearer_token)
    $bot_username = $api.verify_credentials.acct
  elsif $software == InstanceType::MISSKEY
    log "Misskey support not implemented!"
    exit 1
    # $bot_username = /api/i 'username'
  else
    log "Invald instance type!"
    exit 1
  end

  model_path = $bot_username + ".model"

  if !File.file?(model_path)
    Model.consume_all($corpus_path).save(model_path)
  end

  log "Loading model #{model_path}"
  $model = Model.load(model_path)
end

init()

# Post a random tweet every 1 hour
scheduler.every '1h' do
  $api.create_status($model.make_statement)
end

scheduler.every '15s' do
  reply()
end

while true
  sleep 1
end
