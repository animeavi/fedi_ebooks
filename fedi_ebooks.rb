# encoding: utf-8

# rubocop:disable Style/StringLiterals, Style/GlobalVars, Lint/NonLocalExitFromIterator

require "http"
require "http/request"
require "httparty"
require "json"
require "net/http/post/multipart"
require "rufus-scheduler"
require_relative "model"
require_relative "nlp"

$instance_url = ""
$bearer_token = ""
$corpus_path = [""]
$bot_username = ""
$seen_status = {}
$api = nil
$model = nil
$software = 0
$software_string = ""
$mentions_counter = {}
$mentions_counter_timer = {}
$allowed_content_types = %w[text/plain text/html text/markdown text/bbcode]
$reply_length_limit = 300
$username_remote_regex = %r{([@＠][A-Za-z0-9_](?:[A-Za-z0-9_\.]+[A-Za-z0-9_]+|[A-Za-z0-9_]*)[@＠][-a-zA-Z0-9@:%._+\~#=]{2,256}\.[a-z]{2,63}\b(?:[-a-zA-Z0-9@:%\_+.~#?&/=]*))}
$username_local_regex = %r{(?:\s|^.?|[^\p{L}0-9_＠!@#$%&/*]|\s[^\p{L}0-9_＠!@#$%&*])([@＠][A-Za-z0-9_](?:[A-Za-z0-9_\.]+[A-Za-z0-9_]+|[A-Za-z0-9_]*))(?=[^A-Za-z0-9_@＠]|$)}

class InstanceType
  TYPES = [
    MASTODON = 1,
    PLEROMA = 2,
    MISSKEY = 3
  ].freeze
end

class ContentType
  TYPES = [
    PLAIN = "text/plain".freeze,
    HTML = "text/html".freeze,
    MARKDOWN = "text/markdown".freeze,
    BBCODE = "text/bbcode".freeze
  ].freeze
end

scheduler = Rufus::Scheduler.new

def log(*args)
  $stdout.print "@#{$bot_username}: " + args.map(&:to_s).join(" ") + "\n"
  $stdout.flush
end

def reply
  case $software
  when InstanceType::MASTODON, InstanceType::PLEROMA
    reply_mastodon
  when InstanceType::MISSKEY
    reply_misskey
  else
    log "Invalid instance type!"
    exit 1
  end
end

def reply_mastodon
  notifs = get_mentions_notifications

  notifs.each do |n|
    account = n["account"]["acct"]
    status_id = n["status"]["id"]
    is_reblog = !n["reblog"].nil?
    mentions = n["status"]["mentions"]
    notif_id = n["id"]

    # Don't reply to other bots
    if n["account"]["bot"]
      delete_notification(notif_id)
      next
    end

    # Ignore our own status
    if account.downcase == $bot_username.downcase
      delete_notification(notif_id)
      next
    end

    if is_reblog && $bot_username.downcase == n["reblog"]["account"]["acct"].downcase
      # Someone reblogged our status
      delete_notification(notif_id)
      next
    end

    if is_reblog
      delete_notification(notif_id)
      next
    end

    # Avoid responding to duplicate status
    if $seen_status[status_id]
      log "Not handling duplicate status #{status_id}"
      delete_notification(notif_id)
      next
    else
      $seen_status[status_id] = true
    end

    mentions_bot = false
    mentions.each do |m|
      acct = m["acct"]
      if acct.downcase == $bot_username.downcase
        mentions_bot = true
        break
      end
    end

    unless mentions_bot
      delete_notification(notif_id)
      next
    end

    extra_mentions = handle_extra_mentions(mentions, account)

    status_text = NLP.remove_html_tags(n["status"]["content"])
    status_mentionless = get_status_mentionless(status_text, mentions)
    log "Mention from @#{account}: #{status_mentionless}"
    resp = generate_reply(status_mentionless)
    resp = extra_mentions != "" ? "@#{account} #{extra_mentions} #{resp}" : "@#{account} #{resp}"

    log "Replying with: #{resp}"
    create_status(resp, status_id: status_id)
    delete_notification(notif_id)
  end
end

def reply_misskey
  notifs = get_mentions_notifications

  notifs.each do |n|
    account = n["user"]["username"]
    account = "#{account}@#{n["user"]["host"]}" unless n["user"]["host"].nil?
    status_id = n["note"]["id"]
    is_reblog = !n["note"]["renoteId"].nil?
    mentions = n["note"]["mentions"] # Not terribly useful
    notif_id = n["id"]
    content = n["note"]["text"]

    # Ignore read notifications
    next if n["isRead"]

    # Don't reply to other bots
    next if n["user"]["isBot"]
  end
end

def create_status(resp, status_id: nil, content_type: "", media_ids: [])
  if (content_type != "") && ($software != InstanceType::PLEROMA)
    log "Only Pleroma instances support custom content types!"
    exit 1
  end

  headers = {"Content-Type": "application/json",
             "Authorization": "Bearer #{$bearer_token}"}

  body = {}
  body["status"] = resp

  if $allowed_content_types.include? content_type
    body["content_type"] = content_type
  elsif content_type != ""
    log "Invalid content type!"
    log "Allowed content types are: #{$allowed_content_types}"
    exit 1
  end

  body["in_reply_to_id"] = status_id unless status_id.nil?
  body["media_ids"] = media_ids if media_ids.size > 0

  HTTParty.post("#{$instance_url}/api/v1/statuses",
    body: JSON.dump(body), headers: headers)
end

def create_status_misskey(resp, status_id: nil, media_ids: [])
  log "Misskey support not implemented!"
  exit 1
end

# Shamelessly copied from mastodon-api
def upload_media(path)
  headers = {"Authorization": "Bearer #{$bearer_token}"}
  file = File.new(path)
  file = HTTP::FormData::File.new(file)
  body = {file: file}

  response = HTTP.headers(headers).public_send(:post,
    "#{$instance_url}/api/v1/media", form: body)
  JSON.parse(response.body.to_s)["id"]
end

def upload_media_misskey(path)
  file = File.open(path)
  url = URI.parse("#{$instance_url}/api/drive/files/create")

  req = Net::HTTP::Post::Multipart.new(url.path,
    "file": UploadIO.new(file, "application/octet-stream", File.basename(path)),
    "i": $bearer_token)

  n = Net::HTTP.new(url.host, url.port)
  n.use_ssl = (url.scheme == "https")
  response = n.start do |http|
    http.request(req)
  end

  JSON.parse(response.body.to_s)["id"]
end

def get_extra_mentions(mentions)
  extra_mentions = ""

  mentions.each do |m|
    next if m["acct"].downcase == $bot_username.downcase

    extra_mentions = "#{extra_mentions}@#{m["acct"]} "
  end

  extra_mentions.strip
end

def get_mentions_sorted(mentions, account)
  sorted_mentions = ""
  menchies = []
  menchies.push(account)

  mentions.each do |m|
    next if m["acct"].downcase == $bot_username.downcase

    menchies.push(m["acct"])
  end

  menchies.sort!
  menchies.each do |m|
    sorted_mentions = "#{sorted_mentions}@#{m} "
  end

  sorted_mentions.strip
end

def handle_extra_mentions(mentions, account)
  # Remove extra mentions to not spam people after being in the same mention chain 5 times
  extra_mentions = get_extra_mentions(mentions)
  if extra_mentions != ""
    sorted_mentions = get_mentions_sorted(mentions, account)
    if !$mentions_counter[sorted_mentions].nil?
      # Reset after 15 minutes
      if (Process.clock_gettime(Process::CLOCK_MONOTONIC) - $mentions_counter_timer[sorted_mentions]) >= 900
        $mentions_counter[sorted_mentions] = 1
        $mentions_counter_timer[sorted_mentions] = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        return extra_mentions
      elsif $mentions_counter[sorted_mentions] == 5
        return ""
      else
        $mentions_counter[sorted_mentions] = $mentions_counter[sorted_mentions] + 1
        return extra_mentions
      end
    else
      $mentions_counter[sorted_mentions] = 1
      $mentions_counter_timer[sorted_mentions] = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      return extra_mentions
    end
  else
    return extra_mentions
  end
end

def get_status_mentionless(status_text, mentions)
  mentions.each do |m|
    status_text = status_text.gsub("@#{m["acct"]}", "")
  end

  status_text.strip
end

def generate_reply(status_text, limit = $reply_length_limit)
  $model.make_response(status_text, limit)
end

def get_mentions_notifications
  headers = {"Content-Type": "application/json",
             "Authorization": "Bearer #{$bearer_token}"}

  case $software
  when InstanceType::MASTODON
    req_url = "#{$instance_url}/api/v1/notifications?exclude_types[]=follow" \
      "&exclude_types[]=favourite&exclude_types[]=reblog" \
      "&exclude_types[]=poll&exclude_types[]=follow_request"
  when InstanceType::PLEROMA
    req_url = "#{$instance_url}/api/v1/notifications?include_types[]=mention"
  when InstanceType::MISSKEY
    body = {"i": $bearer_token, "includeTypes": ["mention"]}
    headers = {"Content-Type": "application/json"}

    return JSON.parse(HTTParty.post("#{$instance_url}/api/i/notifications",
      body: JSON.dump(body), headers: headers).to_s)
  else
    log "Invalid instance type!"
    exit 1
  end

  JSON.parse(HTTParty.get(req_url, headers: headers).to_s)
end

def delete_notification(id)
  headers = {"Authorization": "Bearer #{$bearer_token}"}

  case $software
  when InstanceType::MASTODON
    req_url = $instance_url + "/api/v1/notifications/#{id}/dismiss"
    HTTParty.post(req_url, headers: headers)
  when InstanceType::PLEROMA
    req_url = $instance_url + "/api/v1/notifications/destroy_multiple?ids[]=#{id}"
    HTTParty.delete(req_url, headers: headers)
  when InstanceType::MISSKEY
    body = {"i": $bearer_token, "notificationId": id}
    HTTParty.post("#{$instance_url}/api/notifications/read",
      body: JSON.dump(body), headers: headers)
  else
    log "Invalid instance type!"
    exit 1
  end
end

def get_software
  begin
    headers = {"Content-Type": "application/json"}
    version = HTTParty.get("#{$instance_url}/api/v1/instance",
      headers: headers)["version"]
    version = version.downcase
    $software = version.include?("pleroma") ? InstanceType::PLEROMA : InstanceType::MASTODON

    return
  rescue
    # Ignored
  end

  begin
    headers = {"Content-Type": "application/json"}
    unless HTTParty.post("#{$instance_url}/api/meta",
      headers: headers)["driveCapacityPerLocalUserMb"].nil?
      $software = InstanceType::MISSKEY

      return
    end
  rescue
    # Ignored
  end
end

def init
  get_software
  case $software
  when InstanceType::MASTODON, InstanceType::PLEROMA
    headers = {"Content-Type": "application/json",
               "Authorization": "Bearer #{$bearer_token}"}
    request = HTTParty.get("#{$instance_url}/api/v1/accounts/verify_credentials",
      headers: headers)

    $bot_username = request["acct"]
    $software_string = $software == InstanceType::MASTODON ? "Mastodon" : "Pleroma"
  when InstanceType::MISSKEY
    log "Misskey support not implemented!"
    exit 1

    body = {"i": $bearer_token}
    headers = {"Content-Type": "application/json"}
    request = JSON.parse(HTTParty.post("#{$instance_url}/api/i",
      body: JSON.dump(body), headers: headers).to_s)

    $bot_username = request["username"]
    $software_string = "Misskey"
  else
    log "Invalid instance type!"
    exit 1
  end

  model_path = "#{$bot_username}.model"

  Model.consume_all($corpus_path).save(model_path) unless File.file?(model_path)

  log "Loading model #{model_path}"
  $model = Model.load(model_path)

  log "Connected to #{$instance_url} (#{$software_string})"
end

init

# Post a random post every 1 hour
scheduler.every "1h" do
  status = $model.make_statement($reply_length_limit)
  log "Posting: #{status}"
  create_status(status)
end

scheduler.every "15s" do
  reply
end

loop do
  sleep 1
end
