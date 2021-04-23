require 'htmlentities'
require 'json'
require 'uri'

# You can get the JSON using something like https://pypi.org/project/mastodon-archive/

archive = File.open("archive.json", "r:UTF-8", &:read)
data = JSON.parse(archive)
statuses = data['statuses']

corpus = File.new("corpus.txt", "w:UTF-8")

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
    content = content.gsub("<br/>", " ")
    content = content.gsub(/<("[^"]*"|'[^']*'|[^'">])*>/, '') # Remove HTML
    content = HTMLEntities.new.decode content.gsub('“', '"').gsub('”', '"').gsub('’', "'").gsub('…', '...')

    next if content.nil?
    mentions = s['mentions']
    mentions.each do |m|
      content = content.gsub("@" + m['acct'], '') || content
      content = content.gsub("@" + m['username'], '') || content
      content = filter(content)
    end

    # I don't remember why I have to call it twice
    content = filter(content)
    if content != ""
      corpus.puts(content)
    end
  end
end

corpus.flush
corpus.close
