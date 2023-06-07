# rubocop:disable Style/FrozenStringLiteralComment
# rubocop:disable Metrics
# rubocop:disable Style/Documentation
# rubocop:disable Style/IfUnlessModifier
# rubocop:disable Style/IdenticalConditionalBranches
# rubocop:disable Style/OptionalBooleanParameter
# rubocop:disable Style/StringLiterals

require "active_record"
require "bulk_insert"
require "csv"
require "set"
require "uri"
require "yajl/json_gem"
require_relative "nlp"
require_relative "../logger"

module FediEbooks
  class Model
    # Database classes
    class Tokens < ActiveRecord::Base
    end

    class Sentences < ActiveRecord::Base
    end

    class Keywords < ActiveRecord::Base
    end

    class Unigrams < ActiveRecord::Base
    end

    class Bigrams < ActiveRecord::Base
    end

    # Reply generation uses this
    INTERIM = -1

    # @return [Array<String>]
    # The top 200 most important keywords, in descending order
    attr_accessor :keywords

    # @return String
    # Path to the database
    attr_accessor :path
    
    # Logger
    attr_reader :logger

    # For Pleroma
    LINEBREAK_PLACEHOLDER = "&_#_1_0_;".freeze
    HTML_LINEBREAK = "&#10;".freeze

    def initialize(path)
      @logger = FediEbooks::Logger.instance
      ActiveRecord::Base.logger = ActiveSupport::Logger.new($stderr)
      ActiveRecord::Base.logger.level = :error

      @path = path
      @tokens = []
      # Reverse lookup tiki by token, for faster generation
      @tikis = {}
    end

    # Shared consume code
    # @param path [String]
    def consume_common(path)
      content = ""
      extension = path.split(".")[-1].downcase

      if extension == "gz"
        extension = path.split(".")[-2].downcase

        require "zlib"
        Encoding.default_external = "UTF-8" # Just in case
        gz = Zlib::GzipReader.new(File.open(path, "rb"))
        content = gz.read
        gz.close
      else
        content = File.read(path, encoding: "utf-8")
      end

      lines = []
      case extension
      when "json"
        @logger.log("Reading json corpus from #{path}")
        json_content = JSON.parse(content)
        twitter_json = content.include?("\"retweeted\": false")

        if twitter_json
          lines = json_content.map do |tweet|
            tweet["text"]
          end
        else
          statuses = json_content.include?("statuses") ? json_content['statuses'] : json_content

          lines = statuses.map do |status|
            pleroma_cleanup(status)
          end

          lines.compact! # Remove nil values
        end
      when "csv"
        @logger.log("Reading CSV corpus from #{path}")
        content = CSV.parse(content)
        header = content.shift
        text_col = header.index("text")
        lines = content.map do |tweet|
          tweet[text_col]
        end
      else
        @logger.log("Reading plaintext corpus from #{path} " \
            "(if this is a json or csv file, please rename the file with an extension and reconsume)")

        lines = content.split("\n")
      end

      lines
    end

    # Consume a corpus into this model
    # @param path [String]
    def consume(path)
      consume_lines(consume_common(path))
    end

    # Consume multiple corpuses into this model
    # @param paths [Array<String>]
    def consume_all(paths)
      lines = []
      paths.each do |path|
        l = consume_common(path)
        lines.concat(l)
      end

      consume_lines(lines)
    end

    # Consume a sequence of lines
    # @param lines [Array<String>]
    def consume_lines(lines)
      @logger.log("Removing commented lines")

      statements = []
      lines.each do |l|
        next if l.start_with?("#") # Remove commented lines

        statements << FediEbooks::NLP.normalize(l)
      end

      text = statements.join("\n").encode("UTF-8", invalid: :replace)

      @logger.log("Tokenizing #{text.count("\n")} statements")
      @sentences = mass_tikify(text)

      @logger.log("Ranking keywords")
      @keywords = FediEbooks::NLP.keywords(text).top(200).map(&:to_s)
      @logger.log("Top keywords: #{@keywords[0]} #{@keywords[1]} #{@keywords[2]}")

      self
    end

    # Generates a response by looking for related sentences
    # in the corpus and building a smaller generator from these
    # @param input [String]
    # @param limit [Integer] characters available for response
    # @return [String]
    def make_response(input, limit = 140)
      setup_db(@path)
      relevant, slightly_relevant = find_relevant_sentences(input)

      if relevant.length >= 3
        unigrams, bigrams = custom_generator(relevant)
        make_statement(limit, relevant, unigrams, bigrams)
      elsif slightly_relevant.length >= 5
        unigrams, bigrams = custom_generator(slightly_relevant)
        make_statement(limit, slightly_relevant, unigrams, bigrams)
      else
        make_statement(limit)
      end
    end

    # Generate some text
    # @param limit [Integer] available characters
    # @param relevant_sentences Array<Array<Integer>>
    # @param unigrams [Hash]
    # @param bigrams [Hash]
    # @param retry_limit [Integer] how many times to retry on invalid tweet
    # @return [String]
    def make_statement(limit = 140, relevant_sentences = nil, unigrams = nil, bigrams = nil, retry_limit = 10)
      setup_db(@path)
      responding = !relevant_sentences.nil?
      retries = 0

      while (tikis = generate_respoding(responding, 3, :bigrams, relevant_sentences, unigrams, bigrams))
        # @logger.log("Attempting to produce tweet try #{retries+1}/#{retry_limit}")
        break if (tikis.length > 3 || responding) && valid_tweet?(tikis, limit)

        retries += 1
        break if retries >= retry_limit
      end

      if verbatim?(tikis) && tikis.length > 3 # We made a verbatim tweet by accident
        # @logger.log("Attempting to produce unigram tweet try #{retries+1}/#{retry_limit}")
        while (tikis = generate_respoding(responding, 3, :unigrams, relevant_sentences, unigrams, bigrams))
          break if valid_tweet?(tikis, limit) && !verbatim?(tikis)

          retries += 1
          break if retries >= retry_limit
        end
      end

      tweet = reconstruct(tikis)

      if retries >= retry_limit
        @logger.log("Unable to produce valid non-verbatim tweet; using \"#{tweet}\"")
      end

      fix(tweet)
    end

    # Gets the keywords from the database as an array
    # @return [Array<String>]
    def get_keywords
      setup_db(@path)
      query = Keywords.all
      keywords = JSON.parse(query.to_json)
      keywords.map(&:values).flatten
    end

    # Set ups the database connection
    # @param path [String]
    def setup_db(path)
      return if ActiveRecord::Base.connected? && ActiveRecord::Base.connection.active?

      ActiveRecord::Base.clear_active_connections!
      ActiveRecord::Base.establish_connection(
        adapter: "sqlite3",
        database: path
      )
    end

    # Creates the database for the model
    # @param path [String]
    def create_db(path)
      setup_db(path)

      ActiveRecord::Schema.define do
        create_table :tokens, id: false, if_not_exists: true do |table|
          table.column :token_id, :integer
          table.column :token, :string
        end

        create_table :sentences, id: false, if_not_exists: true do |table|
          table.column :sentence_id, :integer
          table.column :sentence, :string
        end

        create_table :keywords, id: false, if_not_exists: true do |table|
          table.column :keyword, :string
        end

        create_table :unigrams, id: false, if_not_exists: true do |table|
          table.column :tiki, :integer
          table.column :unigram, :string
        end

        create_table :bigrams, id: false, if_not_exists: true do |table|
          table.column :tiki, :integer
          table.column :next_tiki, :integer
          table.column :bigram, :string
        end
      end
    end

    # Populates the database for the model
    def save
      create_db(@path)

      Tokens.bulk_insert do |worker|
        i = 0
        @tokens.each do |d|
          worker.add token_id: i, token: d
          i += 1
        end
      end

      Sentences.bulk_insert do |worker|
        # Attempting to make the numbers in the array searchable by a SQL statement
        # It will look like this => |10|54|642|

        i = 0
        @sentences.each do |d|
          worker.add sentence_id: i, sentence: array_to_record(d) unless d.empty?
          i += 1
        end
      end

      Keywords.bulk_insert do |worker|
        @keywords.each { |d| worker.add keyword: d }
      end

      # Geneate default Unigrams and Bigrams
      default_generator

      @logger.log("Database file created, run the software again.")
      ActiveRecord::Base.clear_active_connections!
      exit 0
    end

    private

    # Reverse lookup a token index from a token
    # @param token [String]
    # @return [Integer]
    def tikify(token)
      if @tikis.key?(token)
        @tikis[token]
      else
        ((@tokens.length + 1) % 1000).zero? and puts "#{@tokens.length + 1} tokens"
        @tokens << token
        @tikis[token] = @tokens.length - 1
      end
    end

    # Convert a body of text into arrays of tikis
    # @param text [String]
    # @return [Array<Array<Integer>>]
    def mass_tikify(text)
      sentences = FediEbooks::NLP.sentences(text)

      sentences.map do |s|
        tokens = FediEbooks::NLP.tokenize(s).reject do |t|
          # Don't include usernames/urls as tokens
          (t.include?("@") && t.length > 1) || t.include?("http")
        end

        tokens.map { |t| tikify(t) }
      end
    end

    # Builds a proper sentence from a list of tikis
    # @param tikis [Array<Integer>]
    # @return [String]
    def reconstruct(tikis)
      text = ""
      last_token = nil
      tikis.each do |tiki|
        next if tiki == INTERIM

        token = query_token(tiki)
        text += " " if last_token && FediEbooks::NLP.space_between?(last_token, token)
        text += token
        last_token = token
      end

      cleanup_final_text(text)
    end

    # Clean up final text before returning it
    # @param text [String]
    # @return [String]
    def cleanup_final_text(text)
      # Clean stray stuff
      single = ["\"", "'"]
      single.each do |s|
        text = text.gsub(s, "") if text.scan(s).count == 1
      end

      strays = [["(", ")"], ["[", "]"]]
      strays.each do |stray_pair|
        opening = text.scan(stray_pair[0]).count == 1
        closing = text.scan(stray_pair[1]).count == 1
        if opening && !closing
          text = text.gsub(stray_pair[0], "")
        elsif !opening && closing
          text = text.gsub(stray_pair[1], "")
        end
      end

      # Make all spaces single spaces
      text = text.squeeze(" ")
    end

    # Correct encoding issues in generated text
    # @param text [String]
    # @return [String]
    def fix(text)
      FediEbooks::NLP.htmlentities.decode(text)
    end

    # Check if an array of tikis comprises a valid tweet
    # @param tikis [Array<Integer>]
    # @param limit Integer how many chars we have left
    def valid_tweet?(tikis, limit)
      tweet = reconstruct(tikis)
      tweet.length <= limit && !FediEbooks::NLP.unmatched_enclosers?(tweet)
    end

    # Test if a sentence has been copied verbatim from original
    # @param tikis [Array<Integer>]
    # @return [Boolean]
    def verbatim?(tikis)
      !Sentences.where("sentence = ?", array_to_record(tikis)).blank?
    end

    # Cleans up the status for ActivityPub
    # @param status [String]
    # @param html_linebreaks [Boolean] try to replace line breaks with HTML ones
    def pleroma_cleanup(status, html_linebreaks: false)
      return nil unless status['reblog'].nil?

      content = status['content']
      return nil if content.nil?

      # Try to remove line breaks at the start of the post
      10.times do
        content = content.strip.gsub(/^<p>/, "") || content
        content = content.strip.gsub(%r{^<br/>}, "") || content
      end

      content = content.gsub(%r{<a.*?</a>}, "")
      content = content.gsub("<br/>", " ") unless html_linebreaks
      content = content.gsub("<p>", " ") unless html_linebreaks
      content = content.gsub("<br/>", " #{LINEBREAK_PLACEHOLDER} ") if html_linebreaks
      content = content.gsub("<p>", " #{LINEBREAK_PLACEHOLDER} ") if html_linebreaks
      content = content.gsub(/<("[^"]*"|'[^']*'|[^'">])*>/, '') # Remove HTML
      content = content.tr('“', '"').tr('”', '"').tr('’', "'").tr('…', '...')
      content = FediEbooks::NLP.htmlentities.decode(content)

      return nil if content.nil?

      mentions = status['mentions'].nil? ? [] : status['mentions']
      mentions.each do |m|
        content = content.gsub("@#{m['acct']}", '') || content
        content = content.gsub("@#{m['username']}", '') || content
        content = pleroma_filter(content)
      end

      content = pleroma_filter(content)

      if html_linebreaks
        # Try to remove line breaks at the start of the post (again)
        10.times do
          content = content.strip.gsub(/^#{LINEBREAK_PLACEHOLDER}/, "") || content
        end

        content = content.gsub(LINEBREAK_PLACEHOLDER, HTML_LINEBREAK)

        while content.end_with? HTML_LINEBREAK
          if content == HTML_LINEBREAK
            content = ""
            break
          end

          content = content.slice(content.rindex(HTML_LINEBREAK), HTML_LINEBREAK.size)
          content = content.strip
        end

        while content.start_with? HTML_LINEBREAK
          content = content.sub(HTML_LINEBREAK, "")
          content = content.strip
        end
      end

      return content if content != ""

      nil
    end

    # Filter content for ActivityPub
    # @param content [String]
    def pleroma_filter(content)
      content = content.gsub(/\B@\S+\b/, '') || content

      urls = URI.extract(content, %w[http https])
      urls.each do |url|
        content = content.gsub(url, '')
      end

      content = content.squeeze(" ") || content
      content.strip
    end

    # Converts an Integer Array to the "|0|1|2|3|" format for the database
    # @param array [Array<Integer>]
    # @return [String]
    def array_to_record(array)
      "|#{array.join('|')}|"
    end

    # Converts record fom the "|0|1|2|3|" format to an Integer Array
    # @param record [String]
    # @return [Array<Integer>]
    def record_to_array(record)
      record.split("|").reject(&:empty?).map(&:to_i)
    end

    # Generate a recombined sequence of tikis
    # @param passes [Integer] number of times to recombine
    # @param n [Symbol] :unigrams or :bigrams (affects how conservative the model is)
    # @param sentences [Array<Array<Integer>>>]
    # @param unigrams [Hash]
    # @param bigrams [Hash]
    # @return [Array<Integer>]
    def generate(passes = 5, n = :unigrams, sentences = nil, unigrams = nil, bigrams = nil)
      setup_db(@path) unless sentences.nil?

      tikis = []

      while tikis.empty?
        if sentences.nil?
          index = rand(Sentences.count - 1)
          tikis = query_sentence(index)
        else
          index = rand(sentences.count - 1)
          tikis = sentences[index]
        end
      end

      used = tikis # Sentences we"ve already used
      verbatim = [tikis] # Verbatim sentences to avoid reproducing

      0.upto(passes - 1) do
        varsites = {} # Map bigram start site => next tiki alternatives

        i = 0
        tikis.each do |tiki|
          next_tiki = tikis[i + 1]
          break if next_tiki.nil?

          alternatives = []
          if sentences.nil?
            alternatives = n == :unigrams ? query_unigrams(next_tiki) : query_bigrams(tiki, next_tiki)
          elsif (n == :unigrams) && !unigrams.nil?
            alternatives = unigrams[next_tiki] unless unigrams[next_tiki].nil?
          elsif (n == :bigrams) && !bigrams.nil?
            alternatives = bigrams[tiki][next_tiki] unless bigrams[tiki][next_tiki].nil?
          end

          next if alternatives.nil? || alternatives.empty?

          # Filter out suffixes from previous sentences
          alternatives.reject! { |a| a[1] == INTERIM || used.include?(a[0]) }
          varsites[i] = alternatives unless alternatives.empty?
          i += 1
        end

        variant = nil
        varsites.to_a.shuffle.each do |site|
          start = site[0]

          site[1].shuffle.each do |alt|
            temp_sentence = if sentences.nil?
                              query_sentence(alt[0])
                            else
                              sentences[alt[0]]
                            end

            verbatim << temp_sentence
            suffix = temp_sentence[alt[1]..]
            potential = tikis[0..start + 1] + suffix

            # Ensure we"re not just rebuilding some segment of another sentence
            next if verbatim.find { |v| FediEbooks::NLP.subseq?(v, potential) || FediEbooks::NLP.subseq?(potential, v) }

            used << alt[0]
            variant = potential
            break
          end

          break if variant
        end

        # If we failed to produce a variation from any alternative, there
        # is no use running additional passes-- they"ll have the same result.
        break if variant.nil?

        tikis = variant
      end

      tikis
    end

    # This is used only by make_statement
    # @param responding [Boolean] set if a response is being generated or not
    # @param passes [Integer] number of times to recombine
    # @param n [Symbol] :unigrams or :bigrams (affects how conservative the model is)
    # @param sentences [Array<Array<Integer>>>]
    # @param unigrams [Hash]
    # @param bigrams [Hash]
    # @return [Array<Integer>]
    def generate_respoding(responding = false, passes = 5, n = :unigrams, sentences = nil, unigrams = nil,
                           bigrams = nil)
      if responding
        generate(passes, n, sentences, unigrams, bigrams)
      else
        generate(passes, n)
      end
    end

    # Generates the unigrams and bigrams for the full generator,
    # then adds them to the database.
    def default_generator
      @unigrams = {}
      @bigrams = {}

      i = 0
      @sentences.each do |tikis|
        last_tiki = INTERIM

        j = 0
        tikis.each do |tiki|
          @unigrams[last_tiki] ||= []
          @unigrams[last_tiki] << [i, j]

          @bigrams[last_tiki] ||= {}
          @bigrams[last_tiki][tiki] ||= []

          if j == tikis.length - 1 # Mark sentence endings
            @unigrams[tiki] ||= []
            @unigrams[tiki] << [i, INTERIM]
            @bigrams[last_tiki][tiki] << [i, INTERIM]
          else
            @bigrams[last_tiki][tiki] << [i, j + 1]
          end

          last_tiki = tiki
          j += 1
        end

        i += 1
      end

      Unigrams.bulk_insert do |worker|
        @unigrams.each do |key, values|
          values.each do |v|
            unigram = array_to_record(v)
            worker.add tiki: key, unigram: unigram
          end
        end
      end

      Bigrams.bulk_insert do |worker|
        @bigrams.each do |key, subkeys|
          subkeys.each do |subkey, value|
            value.each do |v|
              bigram = array_to_record(v)
              worker.add tiki: key, next_tiki: subkey, bigram: bigram
            end
          end
        end
      end
    end

    # Custom generator used to generate responses to replies
    # @param sentences [Array<Array<Integer>>>]
    # @return unigrams [Hash]
    # @return bigrams [Hash]
    def custom_generator(sentences)
      unigrams = {}
      bigrams = {}

      i = 0
      sentences.each do |tikis|
        last_tiki = INTERIM

        j = 0
        tikis.each do |tiki|
          unigrams[last_tiki] ||= []
          unigrams[last_tiki] << [i, j]

          bigrams[last_tiki] ||= {}
          bigrams[last_tiki][tiki] ||= []

          if j == tikis.length - 1 # Mark sentence endings
            unigrams[tiki] ||= []
            unigrams[tiki] << [i, INTERIM]
            bigrams[last_tiki][tiki] << [i, INTERIM]
          else
            bigrams[last_tiki][tiki] << [i, j + 1]
          end

          last_tiki = tiki
          j += 1
        end

        i += 1
      end

      [unigrams, bigrams]
    end

    # Finds relevant and slightly relevant tokens to use
    # comparing non-stopword token overlaps
    # @param input [String]
    # @return [Array<Array<Integer>, Array<Integer>>]
    def find_relevant_tokens(input)
      relevant = []
      slightly_relevant = []

      tokenized = FediEbooks::NLP.tokenize(input).map(&:downcase)

      tokenized.each do |token|
        token_id_db = find_token_id(token)
        if token_id_db != -1
          relevant << token_id_db unless FediEbooks::NLP.stopword?(token)
          slightly_relevant << token_id_db
        end
      end

      [relevant, slightly_relevant]
    end

    # Finds relevant and slightly relevant tokenized sentences to input
    # comparing non-stopword token overlaps
    # @param input [String]
    # @return [Array<Array<Array<Integer>>, Array<Array<Integer>>>]
    def find_relevant_sentences(input)
      relevant_tokens, slightly_relevant_tokens = find_relevant_tokens(input)

      relevant = relevant_sentences_from_db(relevant_tokens)
      slightly_relevant = relevant_sentences_from_db(slightly_relevant_tokens)

      [relevant, slightly_relevant]
    end

    # Finds relevant sentences on the database for given tokens
    # @param relevant_tokens [Array<Integer>]
    # @return [Array<Array<Integer>>]
    def relevant_sentences_from_db(relevant_tokens)
      relevant = []

      relevant_tokens.each do |token|
        query = Sentences.where("sentence like '%|?|%'", token)
        next if query.blank?

        results = JSON.parse(query.to_json)
        results.each do |res|
          relevant.push(record_to_array(res['sentence']))
        end
      end

      relevant
    end

    # Find a sentence in the database with a given sentence_id
    # @param sentence_id [Integer]
    # @return [Array<Integer>]
    def query_sentence(sentence_id)
      query = Sentences.where("sentence_id = ?", sentence_id)
      return [] if query.blank?

      result = JSON.parse(query.to_json)

      record_to_array(result[0]["sentence"])
    end

    # Finds unigrams in database from a given tiki
    # @param tiki [Integer]
    # @return [Array<Array<Integer>>]
    def query_unigrams(tiki)
      query = Unigrams.where("tiki = ?", tiki)
      results = JSON.parse(query.to_json)

      unigrams = []
      results.each do |r|
        unigrams << record_to_array(r["unigram"])
      end

      unigrams
    end

    # Finds bigrams in database from a given tiki and next_tiki
    # @param tiki [Integer]
    # @param next_tiki [Integer]
    # @return [Array<Array<Integer>>]
    def query_bigrams(tiki, next_tiki)
      query = Bigrams.where("tiki = ? AND next_tiki = ?", tiki, next_tiki)
      results = JSON.parse(query.to_json)

      bigrams = []
      results.each do |r|
        bigrams << record_to_array(r["bigram"])
      end

      bigrams
    end

    # Finds Token in databse for a given Token ID
    # @param token_id [Integer]
    # @return [String]
    def query_token(token_id)
      query = Tokens.where("token_id = ?", token_id)
      result = JSON.parse(query.to_json)

      result[0]["token"]
    end

    # Attempts to find Token ID in database from given token
    # @param token [String]
    # @return [Integer]
    def find_token_id(token)
      query = Tokens.where("lower(token) = ?", token.downcase)
      return -1 if query.blank?

      result = JSON.parse(query.to_json)
      result.sample["token_id"]
    end
  end
end
