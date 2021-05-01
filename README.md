# What is this?

This allows you to run a bot in the fediverse that can reply to posts, make scheduled posts, etc, and whatever you want to add.
I wanted something that used [mispy's twitter_ebooks](https://github.com/mispy/twitter_ebooks) Markov algorithm, as I liked the results, so I built something around it.


# How to use

You need to create an app, and a bearer token for your bot, for your instance, you can Google how to do that for now, I may add a small script to help with that in the future if I feel like it.

With you bearer token in hand, you can edit the following lines in **config.yml**

* `INSTANCE_URL`
* `BEARER_TOKEN`
* `BOT_USERNAME`

The first is your instance's url, the second is the bearer token you generated, and the third one is your bot's username. We will pull the last one from the API, so if you can leave it as is if you want.

You will need a corpus file or files, which will be the source of the bot's posts.

## Corpus file(s)

The bot will need something to generate the posts from, this will usually be your own posts if it's your personal bot, this will be compiled into the model file.

The model code will currently accept everything **twitter_ebooks** did: Twitter archive JSON/CSV files and plain text files.

## Getting the corpus for Mastodon/Pleroma

For Mastodon/Pleroma there's a tool called [mastodon-archive](https://pypi.org/project/mastodon-archive/) for Python, it can be installed with **pip**.

After installed you can archive your posts with the following command

`mastodon-archive archive --no-favourites username@instance.url`

Just follow the steps to authenticate, at the end, it will create a JSON file in the current directory, you can also run this command again to update that file.

While it would be nice to just be able to read from this JSON file, Mastodon/Pleroma uses HTML for the content of your posts, so this makes things a little more complicated, fortunately I made an utility to help with that!

## Converting your Mastodon/Pleroma JSON archive to plain text

Inside of the **util** directory there's a **fedi_archive_to_txt.rb** script that can take that JSON generated by **mastodon-archive** and convert it to plain text.

To use it run the following command (from the main project directory)

`ruby util/fedi_archive_to_txt.rb YOUR_JSON_FILE OUTPUT_TXT_FILE`

The output TXT argument is optional, if you don't use it, it will be saved to **corpus.txt**, now you have a file that can be used for your bot.


Now edit **config.yml** again and modify `CORPUS_FILES` to add the path to your corpus file, this value is a list and can have multiple corpus files (if you wish), like

`CORPUS_FILES: ['corpus.txt', 'file2.txt', 'twitter.json']`

## Installing Ruby dependencies

Make sure you have Ruby and the Bundler gem (`gem install bundler`) installed.

`cd` into the project's directory and run `bundle install`

## Running the bot

Just `cd` into the project's directory and run

`bundle exec ruby fedi_ebooks.rb`

This is fine in some cases, but I recommend creating a service for the bot so it can be restarted automatically and run on boot.