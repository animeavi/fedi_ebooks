require "rufus-scheduler"

require_relative "config"
require_relative "provider"
require_relative "mispy/model"

module FediEbooks
  @model = nil
  @top20 = nil
  @top100 = nil

  @instance = nil
  @logger = FediEbooks::Logger.instance
  @scheduler = Rufus::Scheduler.new

  def self.init
    FediEbooks::Config.from_file("config.yml")

    @instance = FediEbooks::Provider.select_provider()
    FediEbooks::Config.update_bot_username(@instance.get_username)

    if FediEbooks::Config.bot_username.nil?
      @logger.log("Unable to get the account's username! Check your credentials!")
      exit(1)
    end

    model_path = "#{FediEbooks::Config.bot_username}.db"
    @model = FediEbooks::Model.new(model_path)

    if File.file?(model_path)
      @logger.log("Database #{@model.path} loaded.")
    else
      @logger.log("Creating database #{@model.path}...")
      @model.consume_all(FediEbooks::Config.corpus_files).save
    end

    keywords = @model.get_keywords
    @top20 = keywords.take(20)
    @top100 = keywords.take(100)

    @logger.log("Connected to #{FediEbooks::Config.instance_url} (#{@instance.name})")
  end

  init

  # Prettier errors
  def @scheduler.on_error(job, error)
    logger = FediEbooks::Logger.instance
    logger.log("Exception caught in scheduler thread #{error.inspect}!")

    puts("\n------------ Backtrace Below ------------\n\n")

    error.backtrace.each do |line|
      puts(line.to_s)
    end

    puts("\n\n------------ End of Backtrace ------------\n\n")
  end

  # Post a random post every 1 hour
  @scheduler.every "1h" do
    status = @model.make_statement(FediEbooks::Config.reply_max_length)
    @logger.log("Posting: #{status}")
    @instance.create_status(status)
  end

  @scheduler.every "30s" do
    @instance.reply(@model)

    # Comment this out if you want timeline replies
    # @instance.reply_timeline(@model)
  end

  loop do
    sleep 1
  end
end
