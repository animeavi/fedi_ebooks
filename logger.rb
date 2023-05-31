require_relative "config"

module FediEbooks
  class Logger
    def self.log(*args)
      $stdout.print "@#{FediEbooks::Config.bot_username}: #{args.map(&:to_s).join(' ')}\n"
      $stdout.flush
    end
  end
end
