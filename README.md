# What is this?

This allows you to run a bot in the fediverse that can reply to posts, make scheduled posts, etc, and whatever you want to add.
I wanted something that used [mispy's twitter_ebooks](https://github.com/mispy/twitter_ebooks) Markov algorithm, as I liked the results, so I built something around it.


# How to use

You need to create an app, and generate a bearer token for your bot, we have a script for that. You can set those values manually in **config.yml** *or* you can use the script in the next step to do so interactively. 

* `INSTANCE_URL`
* `BOT_USERNAME`

## Generating your bearer token

Included in the root of this repository is **auth_helper.rb**, you can use it to generate a bearer token for your bot and have the option to add it **config.yml**, if you wish. Just run **auth_helper.rb** and follow the interactive prompts.

Next you will need a corpus file or files, which will be the source of the bot's posts.

## Corpus file(s)

The bot will need something to generate the posts from, this will usually be your own posts if it's your personal bot, this will be compiled into the model file.

The model code will currently accept everything **twitter_ebooks** did: Twitter archive JSON/CSV files and plain text files, I added support for Mastodon/Pleroma JSON files, so they can be loaded without manual conversion.

## Getting the corpus for Mastodon/Pleroma

For Mastodon/Pleroma there's a tool called [mastodon-archive](https://pypi.org/project/mastodon-archive/) for Python, it can be installed with **pip**.

After installed you can archive your posts with the following command

`mastodon-archive archive --no-favourites username@instance.url`

Just follow the steps to authenticate, at the end, it will create a JSON file in the current directory, you can also run this command again to update that file. This JSON file can be used as your corpus file to generate the model file.

I have a [modified version of mastodon-archive](https://github.com/animeavi/mastodon-backup) that can pull the archive from uses other than the authed user (you can auth from any instance, but you only get the posts that federated to that instance), figure out how to install it though lole (`python setup.py install` maybe idk.

`mastodon-archive archive --no-favourites --id target-username@instance.url your-username@instance.url`

Edit **config.yml** again and modify `CORPUS_FILES` to add the path to your corpus file, this value is a list and can have multiple corpus files (if you wish), like

```
CORPUS_FILES:
- corpus.json
- corpus.txt
- twitter_corpus.json
```

## Installing Ruby dependencies

Make sure you have Ruby and the Bundler gem (`gem install bundler`) installed.

`cd` into the project's directory and run `bundle install`

## Running the bot

Just `cd` into the project's directory and run

`bundle exec ruby fedi_ebooks.rb`

This is fine in some cases, but I recommend creating a service for the bot so it can be restarted automatically and run on boot.
