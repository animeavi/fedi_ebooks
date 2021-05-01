require 'json'
require 'uri'
require 'net/http'
require 'yaml'

yml_config = "config.yml"
config = YAML.load(File.read(yml_config))

print "Your instance url (leave blank to use config value) [#{config['INSTANCE_URL']}]: "
temp = gets.chomp
instance_url = temp.strip == "" ? config["INSTANCE_URL"] : temp

print "Your bot's username (leave blank to use config value) [#{config["BOT_USERNAME"]}]: "
temp = gets.chomp
bot_username = temp.strip == "" ? config["BOT_USERNAME"] : temp

puts "\nCreating app..."

params = { client_name: bot_username,
           redirect_uris: "urn:ietf:wg:oauth:2.0:oob",
           scopes: "read write follow" }

uri = URI("#{instance_url}/api/v1/apps")
res = Net::HTTP.post_form(uri, params)

data = JSON.parse(res.body)
client_id = data["client_id"]
client_secret = data["client_secret"]

puts "Your app has been created successfully!"
puts "Your Client ID is: #{client_id}}"
puts "Your Client secret is: #{client_secret}}"
puts "\nGenerating bearer token for your bot account..."

params = { client_id: client_id,
           client_secret: client_secret,
           redirect_uri: "urn:ietf:wg:oauth:2.0:oob",
           grant_type: "client_credentials" }

uri = URI("#{instance_url}/oauth/token")
res = Net::HTTP.post_form(uri, params)

data = JSON.parse(res.body)
bearer_token = data["access_token"]

puts "Your Bearer Token has been generate successfully!"
puts "Your Bearer Token is: #{bearer_token}}"

save_cfg = false
print "Save it to #{yml_config}? (y/n) [default: y]: "
temp = gets.chomp.strip.downcase


case temp
when "", "y", "yes"
  save_cfg = true
end

if save_cfg
  puts "Updating #{yml_config} with the generated Bearer Token..."
  config["BEARER_TOKEN"] = bearer_token
  File.open(yml_config, 'w') { |f| YAML.dump(config, f) }
end

puts "\nDone!"
