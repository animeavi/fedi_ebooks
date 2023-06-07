require 'singleton'

module FediEbooks
  class Logger
    include Singleton
    @@name ||= "Logger"

    def log(*args)
      $stdout.print "#{@@name}: #{args.map(&:to_s).join(' ')}\n"
      $stdout.flush
    end

    def set_name(name)
      @@name = name
    end
  end
end
