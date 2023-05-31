require_relative "../config"
require_relative "base"
require_relative "mastodon"

module FediEbooks
  class PleromaProvider < FediEbooks::MastodonProvider
    def name
      "Pleroma"
    end

    def get_mentions_notifications
      headers = { "Content-Type": "application/json",
                  "Authorization": "Bearer #{FediEbooks::Config.bearer_token}" }
      req_url = "#{FediEbooks::Config.instance_url}/api/v1/notifications?include_types[]=mention"

      JSON.parse(HTTParty.get(req_url, headers: headers).to_s)
    end

    def delete_notification(id)
      headers = { "Authorization": "Bearer #{FediEbooks::Config.bearer_token}" }
      req_url = FediEbooks::Config.instance_url + "/api/v1/notifications/destroy_multiple?ids[]=#{id}"

      HTTParty.delete(req_url, headers: headers)
    end
  end
end
