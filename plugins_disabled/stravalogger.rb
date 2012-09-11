=begin
Plugin: Strava Logger
Description: Creates separate entries for rides and runs you finished today
Author: [Patrick Walsh](http://twitter.com/zmre)
Configuration:
  strava_athleteid: "yourid"
  strava_tags: "@social @sports"
Notes:
  - strava_athleteid is a number you can find in the URL when viewing your profile
  - strava_tags are tags you want to add to every entry, e.g. "@social @sports @cycling @training"
=end
require 'rexml/document';
config = {
  'description' => ['strava_athleteid is a number you can find in the URL when viewing your profile',
                    'strava_tags are tags you want to add to every entry, e.g. "@social @sports @cycling @training"'],
  'strava_athleteid' => '',
  'goodreads_tags' => '@social @sports'
}
$slog.register_plugin({ 'class' => 'StravaLogger', 'config' => config })

class StravaLogger < Slogger
  def do_log
    #feed = 'http://pipes.yahoo.com/pipes/pipe.run?_id=04c9130284062eff525dae9f9519bc38&_render=rss&athleteId='
    #feed = 'http://pipes.yahoo.com/pipes/pipe.run?_id=04c9130284062eff525dae9f9519bc38&_render=json&athleteId='
    feed = 'http://www.strava.com/api/v1/rides?athleteId='
    if @config.key?(self.class.name)
      @grconfig = @config[self.class.name]
      if !@grconfig.key?('strava_athleteid') || @grconfig['strava_athleteid'] == ''
        @log.warn("Strava athlete ID has not been configured or is invalid, please edit your slogger_config file.")
        return
      else
        feed += @grconfig['strava_athleteid']
      end
    else
      @log.warn("Strava has not been configured or is invalid, please edit your slogger_config file.")
      return
    end
    @log.info("Logging activities from Strava")

    retries = 0
    success = false
    until success
      if parse_feed(feed)
          success = true
      else
        break if $options[:max_retries] == retries
        retries += 1
        @log.error("Error parsing Strava feed, retrying (#{retries}/#{$options[:max_retries]})")
        sleep 2
      end
      unless success
        @log.fatal("Could not parse feed #{feed}")
      end
    end
  end

  def parse_feed(rss_feed)
    tags = @grconfig['strava_tags'] || ''
    tags = "\n\n#{tags}\n" unless tags == ''

    begin
      res = Net::HTTP.get_response(URI.parse(rss_feed))
    rescue Exception => e
      p e
      raise "ERROR retrieving Strava ride list url: #{rss_feed}"
    end

    return false if res.nil?

    begin
      rides_json = JSON.parse(res.body)
      rides_json['rides'].each {|rides|
        output = ''
        @log.info("Examining ride #{rides['id']}: #{rides['name']}")
        begin
          res2 = Net::HTTP.get_response(URI.parse("http://www.strava.com/api/v1/rides/#{rides['id']}"));
        rescue Exception => e
          p e
          raise "ERROR retrieving Strava ride #{rides['id']}: http://www.strava.com/api/v1/rides/#{rides['id']}"
        end
        ride_json = JSON.parse(res2.body)
        @log.info("Parsed ride #{rides['id']}")
        strava = ride_json['ride']
        date = Time.parse(strava['startDate'])
        if date > @timespan
          # link
          movingTime = Integer(strava['movingTime'])
          movingTimeMM, movingTimeSS = movingTime.divmod(60)
          movingTimeHH, movingTimeMM = movingTimeMM.divmod(60)
          elapsedTime = Integer(strava['elapsedTime'])
          elapsedTimeMM, elapsedTimeSS = elapsedTime.divmod(60)
          elapsedTimeHH, elapsedTimeMM = elapsedTimeMM.divmod(60)
          strava['distance'] *= 0.000621371
          strava['averageSpeed'] *= 2.23694
          strava['maximumSpeed'] *= 0.000621371
          strava['elevationGain'] *= 3.28084
          output += "# Strava Ride - %.2f mi - %dh %dm %ds - %.1f mph - #{strava['name']}\n\n" % [strava['distance'], movingTimeHH, movingTimeMM, movingTimeSS, strava['averageSpeed']] unless strava['name'].nil?
          output += "* **Description**: #{strava['description']}\n" unless strava['description'].nil?
          output += "* **Distance**: %.2f mi\n" % strava['distance'] unless strava['distance'].nil?
          output += "* **Elevation Gain**: %d ft\n" % strava['elevationGain'] unless strava['elevationGain'].nil?
          output += "* **Bike**: #{strava['bike']}\n" unless strava['bike'].nil?
          output += "* **Average Speed**: %.1f mph\n" % strava['averageSpeed'] unless strava['averageSpeed'].nil?
          output += "* **Max Speed**: %.1f mph\n" % strava['maximumSpeed'] unless strava['maximumSpeed'].nil?
          output += "* **Location**: #{strava['location']}\n" unless strava['location'].nil?
          output += "* **Elapsed Time**: %02d:%02d:%02d\n" % [elapsedTimeHH, elapsedTimeMM, elapsedTimeSS] unless strava['elapsedTime'].nil?
          output += "* **Moving Time**: %02d:%02d:%02d\n" % [movingTimeHH, movingTimeMM, movingTimeSS] unless strava['movingTime'].nil?
          output += "* **Link**: http://app.strava.com/rides/#{rides['id']}\n\n"
          options = {}
          options['content'] = "#{output}\n\n#{tags}"
          options['datestamp'] = date.utc.iso8601
          options['starred'] = false
          # TODO: turn location into a Day One location
          options['uuid'] = %x{uuidgen}.gsub(/-/,'').strip
          sl = DayOne.new
          sl.to_dayone(options)
        else
          break
        end
      }
    rescue Exception => e
      p e
      raise "ERROR parsing Strava results from #{rss_feed}"
    end
    return true
  end
end
