module FediEbooks
  class Constants
    @allowed_content_types = %w[text/plain text/html text/markdown text/bbcode]
    @username_remote_regex = %r{([@＠][A-Za-z0-9_](?:[A-Za-z0-9_\.]+[A-Za-z0-9_]+|[A-Za-z0-9_]*)[@＠][-a-zA-Z0-9@:%._+\~#=]{2,256}\.[a-z]{2,63}\b(?:[-a-zA-Z0-9@:%\_+.~#?&/=]*))}
    @username_local_regex = %r{(?:\s|^.?|[^\p{L}0-9_＠!@#$%&/*]|\s[^\p{L}0-9_＠!@#$%&*])([@＠][A-Za-z0-9_](?:[A-Za-z0-9_\.]+[A-Za-z0-9_]+|[A-Za-z0-9_]*))(?=[^A-Za-z0-9_@＠]|$)}

    class << self
      attr_reader :allowed_content_types, :username_remote_regex, :username_local_regex
    end

    class InstanceType
      TYPES = [
        MASTODON = 1,
        PLEROMA = 2,
        MISSKEY = 3
      ].freeze
    end

    class ContentType
      TYPES = [
        PLAIN = "text/plain".freeze,
        HTML = "text/html".freeze,
        MARKDOWN = "text/markdown".freeze,
        BBCODE = "text/bbcode".freeze
      ].freeze
    end
  end
end
