require 'singleton'
require_relative "config"

module FediEbooks
  class Logger
    include Singleton

    def log(*args)
      $stdout.print "@#{FediEbooks::Config.bot_username}: #{args.map(&:to_s).join(' ')}\n"
      $stdout.flush
    end
  end
end
