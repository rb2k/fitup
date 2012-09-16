#!/usr/bin/env ruby
 
require "fitgem"
require "yaml"
 
# Load the existing yml config
config = begin
  Fitgem::Client.symbolize_keys(YAML.load(File.open("fitbit_creds.yml")))
rescue ArgumentError => e
  puts "Could not parse YAML: #{e.message}"
  exit
end
 
client = Fitgem::Client.new(config[:oauth])
 
# With the token and secret, we will try to use them
# to reconstitute a usable Fitgem::Client
if config[:oauth][:token] && config[:oauth][:secret]
  begin
    access_token = client.reconnect(config[:oauth][:token], config[:oauth][:secret])
  rescue Exception => e
    puts "Error: Could not reconnect Fitgem::Client due to invalid keys in fitbit_creds.yml"
    exit
  end
# Without the secret and token, initialize the Fitgem::Client
# and send the user to login and get a verifier token
else
  request_token = client.request_token
  token = request_token.token
  secret = request_token.secret
 
  puts "Go to http://www.fitbit.com/oauth/authorize?oauth_token=#{token} and then enter the verifier code below"
  verifier = gets.chomp
 
  begin
    access_token = client.authorize(token, secret, { :oauth_verifier => verifier })
  rescue Exception => e
    puts "Error: Could not authorize Fitgem::Client with supplied oauth verifier"
    exit
  end
 
  puts 'Verifier is: '+verifier
  puts "Token is:    "+access_token.token
  puts "Secret is:   "+access_token.secret
 
  user_id = client.user_info['user']['encodedId']
  puts "Current User is: "+user_id
 
  config[:oauth].merge!(:token => access_token.token, :secret => access_token.secret, :user_id => user_id)
 
  # Write the whole oauth token set back to the config file
  File.open(".fitgem.yml", "w") {|f| f.write(config.to_yaml) }
end
 
# ============================================================
# Add Fitgem API calls on the client object below this line
 
client.api_unit_system = Fitgem::ApiUnitSystem.METRIC
no_data_file = "status_no_data.yml"
if File.exist?(no_data_file)
  days_without_data = YAML.load(File.open(no_data_file)) 
else
  puts "NO STATUS DATA FOUND! (might be the first run)"
  days_without_data = {'steps'=>Hash.new(0),'sleep'=>Hash.new(0)}
end

Dir.mkdir('data') unless Dir.exist?('data')

date_range = Date.new(2012,06,22)..Date.today-1
date_range.each do |current_date|
  file_prefix = current_date.strftime("%Y_%m_%d")
  
  activities_file = "data/#{file_prefix}_activities.yaml"
  unless File.exist?(activities_file)|| days_without_data['steps'][current_date].to_i >= 14
      activities_data = client.activities_on_date(current_date)
      nr_steps = activities_data['summary']['steps']
      if nr_steps.to_i == 0
        puts "#{activities_file} would contain a zero step count! SKIPPING" 
        days_without_data['steps'][current_date] += 1
      else
        File.open(activities_file, "w") {|f| f.write(activities_data.to_yaml) }
        puts "#{file_prefix}: Saved activies (#{nr_steps} steps)"
      end
  end
  
  sleep_file = "data/#{file_prefix}_sleep.yaml"
  unless File.exist?(sleep_file) || days_without_data['sleep'][current_date].to_i >= 14
    sleep_data = client.sleep_on_date(current_date)
    min_asleep = sleep_data['summary']['totalMinutesAsleep']
    if min_asleep.to_i == 0
      puts "#{sleep_file} would contain a zero minutes count! SKIPPING"
      days_without_data['sleep'][current_date] += 1
    else
      File.open(sleep_file, "w") {|f| f.write(sleep_data.to_yaml) }
      puts "#{file_prefix}: Saved sleep (#{min_asleep} minutes)"
    end
  end
end

File.open(no_data_file, "w") {|f| f.write(days_without_data.to_yaml) }


