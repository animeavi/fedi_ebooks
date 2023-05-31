require_relative "base"

module FediEbooks
  class MisskeyProvider < FediEbooks::BaseProvider
    def name
      "Misskey"
    end

    def reply(model)
      support_not_implemented # TODO: finish implementing

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
        if n["user"]["isBot"] ||
           FediEbooks::Config.bot_blacklist.include?(account.downcase) ||
           account.include?("botsin.space")
          next
        end
      end
    end

    def upload_media(path)
      file = File.open(path)
      url = URI.parse("#{FediEbooks::Config.instance_url}/api/drive/files/create")

      req = Net::HTTP::Post::Multipart.new(url.path,
                                           "file": UploadIO.new(file, "application/octet-stream", File.basename(path)),
                                           "i": FediEbooks::Config.bearer_token)

      n = Net::HTTP.new(url.host, url.port)
      n.use_ssl = (url.scheme == "https")
      response = n.start do |http|
        http.request(req)
      end

      JSON.parse(response.body.to_s)["id"]
    end

    def get_mentions_notifications
      body = { "i": FediEbooks::Config.bearer_token, "includeTypes": ["mention"] }
      headers = { "Content-Type": "application/json" }

      JSON.parse(HTTParty.post("#{FediEbooks::Config.instance_url}/api/i/notifications",
                               body: JSON.dump(body), headers: headers).to_s)
    end

    def delete_notification(id)
      headers = { "Authorization": "Bearer #{FediEbooks::Config.bearer_token}" }
      body = { "i": FediEbooks::Config.bearer_token, "notificationId": id }
      HTTParty.post("#{FediEbooks::Config.instance_url}/api/notifications/read",
                    body: JSON.dump(body), headers: headers)
    end

    def get_username
      body = { "i": FediEbooks::Config.bearer_token }
      headers = { "Content-Type": "application/json" }
      request = JSON.parse(HTTParty.post("#{FediEbooks::Config.instance_url}/api/i",
                                         body: JSON.dump(body), headers: headers).to_s)

      request["username"]
    end

    def reply_timeline(model)
      support_not_implemented # TODO: implement
    end

    def create_status(resp, status_id: nil, content_type: "", media_ids: [])
      support_not_implemented # TODO: implement
    end

    def get_id_from_username(account)
      support_not_implemented # TODO: implement
    end

    def follow_account(account)
      support_not_implemented # TODO: implement
    end

    def unfollow_account(account)
      support_not_implemented # TODO: implement
    end

    def get_extra_mentions(mentions, account)
      support_not_implemented # TODO: implement
    end

    def get_mentions_sorted(mentions, account)
      support_not_implemented # TODO: implement
    end

    def get_status_mentionless(status_text, mentions)
      support_not_implemented # TODO: implement
    end
  end
end
