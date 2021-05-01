require 'htmlentities'
require 'json'
require 'uri'

# You can get the JSON using something like https://pypi.org/project/mastodon-archive/

archive = File.open("archive.json", "r:UTF-8", &:read)
data = JSON.parse(archive)
statuses = data['statuses']

corpus = File.new("corpus.txt", "w:UTF-8")

# Enable if you want the archive to have HTML line breaks
# You do have to make the bot post with HTML (only Pleroma supports it?)
html_linebreaks = false
LINEBREAK_PLACEHOLDER = "____LLLLINNEE___BBBBREAKER____" # lol

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

      content = content.gsub("#{LINEBREAK_PLACEHOLDER}", "&#10;")

      r = "&#10;"
      while content.end_with? r
        if content == r
          content = ""
          break
        end

        content = content.slice(content.rindex(r), r.size)
        content = content.strip
      end

      while content.start_with? r
        content = content.sub(r, '')
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