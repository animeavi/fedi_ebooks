require_relative "base"

module FediEbooks
  class MastodonProvider < FediEbooks::BaseProvider
    def name
      "Mastodon"
    end

    def reply(model)
      notifs = get_mentions_notifications

      notifs.each do |n|
        account = n["account"]["acct"]
        status_id = n["status"]["id"]
        is_reblog = !n["reblog"].nil?
        mentions = n["status"]["mentions"]
        notif_id = n["id"]

        # You're not funny
        if mentions.size > 8
          delete_notification(notif_id)
          next
        end

        # Don't reply to other bots
        if n["account"]["bot"] ||
           FediEbooks::Config.bot_blacklist.include?(account.downcase) ||
           account.include?("botsin.space")
          delete_notification(notif_id)
          next
        end

        # Ignore our own status
        if account.downcase == FediEbooks::Config.bot_username.downcase
          delete_notification(notif_id)
          next
        end

        if is_reblog &&
           FediEbooks::Config.bot_username.downcase == n["reblog"]["account"]["acct"].downcase
          # Someone reblogged our status
          delete_notification(notif_id)
          next
        end

        if is_reblog
          delete_notification(notif_id)
          next
        end

        # Avoid responding to duplicate status
        if @seen_status[status_id]
          @logger.log("Not handling duplicate status #{status_id}")
          delete_notification(notif_id)
          next
        else
          @seen_status[status_id] = true
        end

        mentions_bot = false
        mentions.each do |m|
          if m["acct"].downcase == FediEbooks::Config.bot_username.downcase
            mentions_bot = true
            break
          end
        end

        unless mentions_bot
          delete_notification(notif_id)
          next
        end

        if detect_infinite_loop(account)
          @logger.log("Infinite loop detected from @#{account}!")
          delete_notification(notif_id)
          next
        end

        extra_mentions = handle_extra_mentions(mentions, account)

        status_text = NLP.remove_html_tags(n["status"]["content"])
        status_mentionless = get_status_mentionless(status_text, mentions)
        @logger.log("Mention from @#{account}: #{status_mentionless}")
        resp = generate_reply(model, status_mentionless)
        resp = extra_mentions != "" ? "@#{account} #{extra_mentions} #{resp}" : "@#{account} #{resp}"

        @logger.log("Replying with: #{resp}")
        create_status(resp, status_id: status_id)
        delete_notification(notif_id)
      end
    end

    def reply_timeline(model)
      headers = { "Content-Type": "application/json",
                  "Authorization": "Bearer #{FediEbooks::Config.bearer_token}" }
      tl = HTTParty.get("#{FediEbooks::Config.instance_url}/api/v1/timelines/home?since_id=#{$last_id_tl}",
                        headers: headers)
      return if tl.key?("errors")

      i = 0
      tl.each do |t|
        if i.zero?
          $last_id_tl = t["id"]
          i = 1
        end

        account = t["account"]["acct"]
        status_id = t["id"]
        is_reblog = !t["reblog"].nil?
        mentions = t["mentions"]

        next if @seen_status[status_id]
        next if t["account"]["bot"]
        next if FediEbooks::Config.bot_blacklist.include?(account.downcase)
        next if account.include?("botsin.space")
        next if account.downcase == FediEbooks::Config.bot_username.downcase
        next if is_reblog

        mentions_bot = false
        mentions.each do |m|
          if m["acct"].downcase == FediEbooks::Config.bot_username.downcase
            mentions_bot = true
            break
          end
        end

        next if mentions_bot

        status_text = NLP.remove_html_tags(t["content"])
        status_mentionless = get_status_mentionless(status_text, mentions)

        tokens = NLP.tokenize(status_mentionless)
        interesting = tokens.find { |tk| $top100.include?(tk.downcase) }
        very_interesting = tokens.find { |tk| $top20.include?(tk.downcase) }

        should_reply = false
        if very_interesting
          should_reply = true if rand < 0.05
        elsif interesting
          should_reply = true if rand < 0.005
        end

        if should_reply
          @logger.log("Post on the TL from @#{account}: #{status_mentionless}")

          extra_mentions = handle_extra_mentions(mentions, account)
          resp = generate_reply(model, status_mentionless)
          resp = extra_mentions != "" ? "@#{account} #{extra_mentions} #{resp}" : "@#{account} #{resp}"

          @logger.log("Replying with: #{resp}")
          create_status(resp, status_id: status_id)
        end

        break # Only try the first valid status
      end
    end

    def create_status(resp, status_id: nil, content_type: "", media_ids: [])
      headers = { "Content-Type": "application/json",
                  "Authorization": "Bearer #{FediEbooks::Config.bearer_token}" }

      body = {}
      body["status"] = resp

      if Constants.allowed_content_types.include? content_type
        body["content_type"] = content_type
      elsif content_type != ""
        @logger.log("Invalid content type!")
        @logger.log("Allowed content types are: #{Constants.allowed_content_types}")
        exit(1)
      end

      body["in_reply_to_id"] = status_id unless status_id.nil?
      body["media_ids"] = media_ids if media_ids.size.positive?

      HTTParty.post("#{FediEbooks::Config.instance_url}/api/v1/statuses",
                    body: JSON.dump(body), headers: headers)
    end

    def upload_media(path)
      headers = { "Authorization": "Bearer #{FediEbooks::Config.bearer_token}" }
      file = File.new(path)
      file = HTTP::FormData::File.new(file)
      body = { file: file }

      response = HTTP.headers(headers).public_send(:post,
                                                   "#{FediEbooks::Config.instance_url}/api/v1/media",
                                                   form: body)

      JSON.parse(response.body.to_s)["id"]
    end

    def get_id_from_username(account)
      headers = { "Content-Type": "application/json",
                  "Authorization": "Bearer #{FediEbooks::Config.bearer_token}" }

      req_url = FediEbooks::Config.instance_url + "/api/v1/accounts/#{account}"
      resp = JSON.parse(HTTParty.get(req_url, headers: headers).to_s)

      resp["id"]
    end

    def follow_account(account)
      headers = { "Content-Type": "application/json",
                  "Authorization": "Bearer #{FediEbooks::Config.bearer_token}" }

      account = get_id_from_username(account)
      req_url = FediEbooks::Config.instance_url + "/api/v1/accounts/#{account}/follow"
      HTTParty.post(req_url, headers: headers)
    end

    def unfollow_account(account)
      headers = { "Content-Type": "application/json",
                  "Authorization": "Bearer #{FediEbooks::Config.bearer_token}" }

      account = get_id_from_username(account)
      req_url = FediEbooks::Config.instance_url + "/api/v1/accounts/#{account}/unfollow"
      HTTParty.post(req_url, headers: headers)
    end

    def get_extra_mentions(mentions, account)
      extra_mentions = ""

      mentions.each do |m|
        next if m["acct"].downcase == FediEbooks::Config.bot_username.downcase
        next if m["acct"].downcase == account.downcase

        extra_mentions = "#{extra_mentions}@#{m["acct"]} "
      end

      extra_mentions.strip
    end

    def get_mentions_sorted(mentions, account)
      sorted_mentions = ""
      menchies = []
      menchies.push(account)

      mentions.each do |m|
        next if m["acct"].downcase == FediEbooks::Config.bot_username.downcase
        next if m["acct"].downcase == account.downcase

        menchies.push(m["acct"])
      end

      menchies.sort!
      menchies.each do |m|
        sorted_mentions = "#{sorted_mentions}@#{m} "
      end

      sorted_mentions.strip
    end

    def get_status_mentionless(status_text, mentions)
      mentions.each do |m|
        status_text = status_text.gsub("@#{m["acct"]}", "")
        status_text = status_text.gsub("@#{m["username"]}", "")
      end

      status_text.strip
    end

    def get_mentions_notifications
      headers = { "Content-Type": "application/json",
                  "Authorization": "Bearer #{FediEbooks::Config.bearer_token}" }
      req_url = "#{FediEbooks::Config.instance_url}/api/v1/notifications?exclude_types[]=follow" \
      "&exclude_types[]=favourite&exclude_types[]=reblog" \
      "&exclude_types[]=poll&exclude_types[]=follow_request"

      JSON.parse(HTTParty.get(req_url, headers: headers).to_s)
    end

    def delete_notification(id)
      headers = { "Authorization": "Bearer #{FediEbooks::Config.bearer_token}" }
      req_url = FediEbooks::Config.instance_url + "/api/v1/notifications/#{id}/dismiss"
      HTTParty.post(req_url, headers: headers)
    end

    def get_username
      headers = { "Content-Type": "application/json",
                  "Authorization": "Bearer #{FediEbooks::Config.bearer_token}" }
      request = HTTParty.get("#{FediEbooks::Config.instance_url}/api/v1/accounts/verify_credentials",
                             headers: headers)

      request["acct"]
    end
  end
end
