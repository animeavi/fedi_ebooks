require "http"
require "http/request"
require "httparty"
require "net/http/post/multipart"
require "rufus-scheduler"
require "yajl/json_gem"

require_relative "../config"
require_relative "../logger"
require_relative "../mispy/model"
require_relative "../mispy/nlp"

module FediEbooks
  class BaseProvider
    @accounts_mentioning
    @accounts_mentioning_stored_time
    @mentions_counter
    @mentions_counter_timer
    @seen_status

    def name
      "Base"
    end

    def initialize
      @accounts_mentioning = {}
      @accounts_mentioning_stored_time = nil
      @mentions_counter = {}
      @mentions_counter_timer = {}
      @seen_status = {}
    end

    def support_not_implemented
      raise StandardError.new("The #{name} provider does not support this operation!")
      exit(1)
    end

    def generate_reply(model, status_text, limit = FediEbooks::Config.reply_max_length)
      model.make_response(status_text, limit)
    end

    def handle_extra_mentions(mentions, account)
      # Remove extra mentions to not spam people after being in the same mention chain 5 times
      extra_mentions = get_extra_mentions(mentions, account)
      if extra_mentions != ""
        sorted_mentions = get_mentions_sorted(mentions, account)
        if !@mentions_counter[sorted_mentions].nil?
          # Reset after 15 minutes
          if (Process.clock_gettime(Process::CLOCK_MONOTONIC) - @mentions_counter_timer[sorted_mentions]) >= 900
            @mentions_counter[sorted_mentions] = 1
            @mentions_counter_timer[sorted_mentions] = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            extra_mentions
          elsif @mentions_counter[sorted_mentions] == 5
            ""
          else
            @mentions_counter[sorted_mentions] = @mentions_counter[sorted_mentions] + 1
            extra_mentions
          end
        else
          @mentions_counter[sorted_mentions] = 1
          @mentions_counter_timer[sorted_mentions] = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          extra_mentions
        end
      else
        extra_mentions
      end
    end

    def detect_infinite_loop(account)
      if @accounts_mentioning_stored_time.nil?
        @accounts_mentioning_stored_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        return false
      elsif (Process.clock_gettime(Process::CLOCK_MONOTONIC) - @accounts_mentioning_stored_time) >= 300
        # Reset after 5 minutes
        @accounts_mentioning_stored_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @accounts_mentioning = {}
      end

      if !@accounts_mentioning[account].nil?
        # If we detect 10 or more posts in 5 minutes we assume it's an infinite loop (another bot)
        return true if @accounts_mentioning[account] >= 10

        @accounts_mentioning[account] = @accounts_mentioning[account] + 1
      else
        @accounts_mentioning[account] = 1
      end

      false
    end

    def reply(model)
      support_not_implemented
    end

    def reply_timeline(model)
      support_not_implemented
    end

    def create_status(resp, status_id: nil, content_type: "", media_ids: [])
      support_not_implemented
    end

    def upload_media(path)
      support_not_implemented
    end

    def get_id_from_username(account)
      support_not_implemented
    end

    def follow_account(account)
      support_not_implemented
    end

    def unfollow_account(account)
      support_not_implemented
    end

    def get_extra_mentions(mentions, account)
      support_not_implemented
    end

    def get_mentions_sorted(mentions, account)
      support_not_implemented
    end

    def get_status_mentionless(status_text, mentions)
      support_not_implemented
    end

    def get_mentions_notifications
      support_not_implemented
    end

    def delete_notification(id)
      support_not_implemented
    end

    def get_username
      support_not_implemented
    end
  end
end
