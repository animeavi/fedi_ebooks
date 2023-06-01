require "httparty"

require_relative "config"
require_relative "constants"
require_relative "logger"
require_relative "providers/pleroma"
require_relative "providers/mastodon"
require_relative "providers/misskey"

module FediEbooks
  class Provider
    @logger = FediEbooks::Logger.instance

    def self.select_provider
      case get_software
      when FediEbooks::Constants::InstanceType::PLEROMA
        FediEbooks::PleromaProvider.new
      when FediEbooks::Constants::InstanceType::MASTODON
        FediEbooks::MastodonProvider.new
      when FediEbooks::Constants::InstanceType::MISSKEY
        FediEbooks::MisskeyProvider.new
      else
        @logger.log("Invalid instance type!")
        exit(1)
      end
    end

    def self.get_software
      begin
        headers = { "Content-Type": "application/json" }
        version = HTTParty.get("#{FediEbooks::Config.instance_url}/api/v1/instance",
                               headers: headers)["version"]
        version = version.downcase

        if version.include?("pleroma") || version.include?("akkoma")
          return FediEbooks::Constants::InstanceType::PLEROMA
        else
          return FediEbooks::Constants::InstanceType::MASTODON
        end
      rescue
        # Ignored
      end

      begin
        headers = { "Content-Type": "application/json" }
        unless HTTParty.post("#{FediEbooks::Config.instance_url}/api/meta",
                             headers: headers)["driveCapacityPerLocalUserMb"].nil?
          FediEbooks::Constants::InstanceType::MISSKEY
        end
      rescue
        # Ignored
      end
    end
  end
end
