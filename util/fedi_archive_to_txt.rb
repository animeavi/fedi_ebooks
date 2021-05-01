require 'htmlentities'
require 'json'
require 'uri'

if ARGV.length != 1 and ARGV.length != 2
  puts "Usage: ruby #{$0} <input_json> [output_txt]"
  puts "Default output file name will be 'corpus.txt'"
  exit 1
end

outfile = (ARGV[1].nil?) ? "corpus.txt" : ARGV[1]

# You can get the JSON using something like https://pypi.org/project/mastodon-archive/

archive = File.open(ARGV[0], "r:UTF-8", &:read)


data = JSON.parse(archive)
statuses = data['statuses'] unless data['statuses'].nil?
statuses = data if data['statuses'].nil?

corpus = File.new(outfile, "w:UTF-8")

# Enable if you want the archive to have HTML line breaks
# You do have to make the bot post with HTML (only Pleroma supports it?)
html_linebreaks = false
LINEBREAK_PLACEHOLDER = "&_#_1_0_;"
HTML_LINEBREAK = "&#10;"

def filter(content)
  content = content.gsub(/\B[@]\S+\b/, '') || content

  urls = URI.extract(content, ['http', 'https'])
  urls.each do |url|
    content = content.gsub(url, '')
  end

  content = content.squeeze(" ") || content
  content.strip
end

statuses.each do |s|
  if s['reblog'].nil?
    content = s['content']

    # Try to remove line breaks at the start of the post
    10.times do
      content = content.strip.gsub(/^<p>/, "") || content
      content = content.strip.gsub(/^<br\/>/, "") || content
    end

    content = content.gsub("<br/>", " ") unless html_linebreaks
    content = content.gsub("<p>", " ") unless html_linebreaks
    content = content.gsub("<br/>", " #{LINEBREAK_PLACEHOLDER} ") if html_linebreaks
    content = content.gsub("<p>", " #{LINEBREAK_PLACEHOLDER} ") if html_linebreaks
    content = content.gsub(/<("[^"]*"|'[^']*'|[^'">])*>/, '') # Remove HTML
    content = HTMLEntities.new.decode content.gsub('“', '"').gsub('”', '"').gsub('’', "'").gsub('…', '...')

    next if content.nil?
    mentions = s['mentions']
    mentions.each do |m|
      content = content.gsub("@" + m['acct'], '') || content
      content = content.gsub("@" + m['username'], '') || content
      content = filter(content)
    end

    content = filter(content)

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

    if content != ""
      corpus.puts(content)
    end
  end
end

corpus.flush
corpus.close
