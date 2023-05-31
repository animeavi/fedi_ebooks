# What is this?

This allows you to run a bot in the fediverse that can reply to posts, make scheduled posts, etc, and whatever you want to add.
I wanted something that used [mispy's twitter_ebooks](https://github.com/mispy/twitter_ebooks) Markov algorithm, as I liked the results, so I built something around it.


# How to use

You need to create an app, and generate a bearer token for your bot, we have a script for that. You can set those values manually in **config.yml** *or* you can use the script in the next step to do so interactively. 

* `INSTANCE_URL`
* `BOT_USERNAME`

## Generating your bearer token

Included in the **util** directory of this repository is **auth_helper.rb**, you can use it to generate a bearer token for your bot and have the option to add it **config.yml**, if you wish. Just run **auth_helper.rb** and follow the interactive prompts.

Next you will need a corpus file or files, which will be the source of the bot's posts.

## Corpus file(s)

The bot will need something to generate the posts from, this will usually be your own posts if it's your personal bot, this will be compiled into the model file.

The model code will currently accept everything **twitter_ebooks** did: Twitter archive JSON/CSV files and plain text files, I added support for Mastodon/Pleroma JSON files, so they can be loaded without manual conversion.

## Getting the corpus for Mastodon/Pleroma

For Mastodon/Pleroma there's a tool called [mastodon-archive](https://pypi.org/project/mastodon-archive/) for Python, it can be installed with **pip**.

After installed you can archive your posts with the following command (warning: this will pull Direct Message posts too, use my fork below if you want to avoid that)

`mastodon-archive archive --no-favourites username@instance.url`

Just follow the steps to authenticate, at the end, it will create a JSON file in the current directory, you can also run this command again to update that file. This JSON file can be used as your corpus file to generate the model file.

I have a [modified version of mastodon-archive](https://github.com/animeavi/mastodon-backup) that can pull the archive from uses other than the authed user (you can auth from any instance, but you only get the posts that federated to that instance), figure out how to install it though lole (`python setup.py install` maybe idk)

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
Also, it is recommended to run the bot once to generate the .model file and then restart, to decrease memory usage that is experienced when generating it. Depending on the size of the corpus file, you may want to have a swap file on your server or generate the .model on your desktop/laptop before uploading it to the server, as it may use a lot of memory for this process, but you only need to do this once and whenever you update the archive.


## Creating a service (systemd and OpenRC)

I've included an example service file for systemd called `example.service` and one for OpenRC called `example.openrc` in the **util** directory, but you’ll have to edit some of this stuff to match your system.


First install GNU Screen:

`sudo apt install screen` (Debian/Ubuntu)

`sudo pacman -S screen` (Arch) 

### systemd
Create the service file (you may not have nano installed by default, eg: Arch, install it)

`sudo nano /etc/systemd/system/fediebooks.service`

Paste the contents of the example file here.

Where it says `User=`, edit with your Linux username.

Edit everywhere that says `/path/to/your/bot/files` to the folder where your bot files are.

Edit `/home/user/.gem/ruby/3.0.0/bin/bundler` to what the command `which bundler` gives you

Edit `/usr/bin/ruby` to what the command `which ruby` gives you (should match most systems already)

Save the file (CTRL+S).

Run
```
sudo systemctl enable fediebooks
sudo systemctl start fediebooks
```

Now the service should be running and start automatically on boot.

### OpenRC
Create the service file (you may not have nano installed by default, eg: Arch, install it)

`sudo nano /etc/init.d/fediebooks`

Paste the contents of the example file here.

Where it says `command_user=`, edit with your Linux username.

Edit everywhere that says `/path/to/your/bot/files` to the folder where your bot files are.

Edit `/home/user/.gem/ruby/3.0.0/bin/bundler` to what the command `which bundler` gives you

Edit `/usr/bin/ruby` to what the command `which ruby` gives you (should match most systems already)

Save the file (CTRL+S).

Run
```
sudo chmod +x /etc/init.d/fediebooks
sudo rc-update add fediebooks default
sudo rc-service fediebooks start
```

Now the service should be running and start automatically on boot.


## Monitoring the bot
To check on the bot's console output while it's running: `screen -r fediebooks`

To leave without killing the screen hold CTRL then press A, D.
