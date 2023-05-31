require "yaml"

module FediEbooks
  class Config
    @instance_url
    @bearer_token
    @corpus_files
    @bot_username
    @reply_max_length
    @bot_blacklist

    def self.from_file(config_file)
      config = YAML.safe_load(File.read(config_file))
      @instance_url = config["INSTANCE_URL"]
      @bearer_token = config["BEARER_TOKEN"]
      @corpus_files = config["CORPUS_FILES"]
      @bot_username = config["BOT_USERNAME"]
      @reply_max_length = config["REPLY_LENGTH"]
      @bot_blacklist = config["BOT_BLACKLIST"] ? config["BOT_BLACKLIST"].map(&:downcase) : []
    end

    def self.instance_url
      @instance_url
    end

    def self.bearer_token
      @bearer_token
    end

    def self.corpus_files
      @corpus_files
    end

    def self.bot_username
      @bot_username
    end

    def self.reply_max_length
      @reply_max_length
    end

    def self.bot_blacklist
      @bot_blacklist
    end

    def self.update_bot_username(new_username)
      @bot_username = new_username
    end
  end
end
