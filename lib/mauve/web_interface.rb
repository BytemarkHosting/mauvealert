# encoding: UTF-8
require 'haml'
require 'redcloth'
require 'json'

require 'mauve/authentication'
require 'mauve/http_server'

tilt_lib = "tilt"
begin
  require tilt_lib
rescue LoadError => ex
  if tilt_lib == "tilt"
    tilt_lib = "sinatra/tilt" 
    retry
  end
  
  raise ex
end

require 'sinatra/base'
require 'sinatra-partials'

require 'rack'
require 'rack-flash'

if !defined?(JRUBY_VERSION)
  require 'thin'
end

module Mauve
  # Our Sinatra app proper
  #
  class WebInterface < Sinatra::Base
    
    def self._logger
      Log4r::Logger.new(self.to_s)
    end
    
    #
    # Generic URL for 
    #
    def self.url_for(obj)
      [Mauve::HTTPServer.instance.base_url, obj.class.to_s.split("::").last.downcase, obj.id.to_s].join("/")
    end
    
    use Rack::CommonLogger
    use Rack::Chunked
    use Rack::ContentLength
    use Rack::Flash

    # Ugh.. hacky way to dynamically configure the document root.
    set :root, Proc.new{ HTTPServer.instance.document_root }
    set :views, Proc.new{ root && File.join(root, 'views') }
    set :public,  Proc.new{ root && File.join(root, 'static') }
    set :static, true
    set :show_exceptions, true

    logger = _logger
    #
    # The next two lines are not needed.
    #
    # set :logging, true
    # set :logger, logger
    set :dump_errors, true      # ...will dump errors to the log
    set :raise_errors, false    # ...will not let exceptions out to main program
    set :show_exceptions, false # ...will not show exceptions

    #
    # Default template.
    #
    template :layout do
      <<EOF
!!! 5
%html
  = partial('head')
  %body
    =partial("navbar")
    =yield 
EOF
    end   


 
    ###########################################/alert#############################
    
    before do
      @title = "Mauve:"
      @person = nil
      #
      # Make sure we're authenticated.
      #
      if session.has_key?('username') and Configuration.current.people.has_key?(session['username'].to_s)
        # 
        # Phew, we're authenticated
        #
        @person = Configuration.current.people[session['username'].to_s]

        #
        # Set remote user for logging.
        #
        env['REMOTE_USER'] = @person.username

        #
        # Don't cache ajax requests
        #
        cache_control :no_cache if request.xhr?

        #
        # Set up some defaults.
        #
        @group_by = "subject"
        @alerts_ackd = []
        @alerts_cleared = []
        @alerts_raised = []
      else
        # Uh-oh.. Intruder alert!
        #
        ok_urls = %w(/ /login /logout)
        no_redirect_urls = %w(/ajax)

        unless ok_urls.include?(request.path_info) 
          flash['error'] = "You must be logged in to access that page."
          redirect "/login?next_page=#{request.path_info}" unless no_redirect_urls.any?{|u| /^#{u}/ =~ request.path_info }
        end
      end      
    end
    
    get '/' do
      if @person.nil?
        redirect '/login' 
      else
        redirect '/alerts'
      end
    end
    
    ########################################################################
    
    ## Checks the identity of the person via a password.
    #
    # The password can be either the SSO or a local one defined 
    # in the configuration file.
   
    get '/login' do
      @title += " Login"
      if @person
        redirect '/'
      else
        @username = nil
        @next_page = params[:next_page] || '/'
        status 403 if flash['error']
        haml :login
      end
    end
 
    post '/login' do
      usr = params['username'].to_s
      pwd = params['password'].to_s
      next_page = params['next_page'] || "/"
      
      #
      # Make sure we don't magically logout automatically :)
      #
      next_page = '/' if next_page == '/logout'

      if Authentication.authenticate(usr, pwd)
        session['username'] = usr
        # Clear the flash.
        flash['error'] = nil 
        redirect next_page
      else
        flash['error'] = "Authentication failed."
        status 401
#        redirect "/login?next_page=#{next_page}"
        @title += " Login"
        @username = usr
        @next_page = next_page
        haml :login
      end
    end
    
    get '/logout' do
      session.delete('username')
      flash['info'] = "You have logged out!"
      redirect '/login'
    end
 
    #=======
    # This is the main alerts handler.
    #
       
    get '/alerts' do 
      redirect '/alerts/raised'
    end

    get '/alerts/:alert_type' do
      redirect "/alerts/#{params[:alert_type]}/subject"
    end

    get '/alerts/:alert_type/:group_by' do 

      return haml(:not_implemented) unless %w(raised acknowledged).include?(params[:alert_type])

      alerts_table(params)

      haml(:alerts)
    end

    post '/alerts/acknowledge' do
      #
      # TODO: error check inputs
      #
      # ack_until is in milliseconds!
      ack_until  = params[:ack_until]
      n_hours    = params[:n_hours]    || 2
      type_hours = params[:type_hours] || "daytime"
      alerts     = params[:alerts]     || []
      note       = params[:note]       || nil

      n_hours = (n_hours.to_f > 188 ? 188 : n_hours.to_f)
      type_hours = "daytime" unless %w(daytime working wallclock).include?(type_hours)

      if ack_until.to_s.empty?
        now = Time.now
        now.bank_holidays = Server.instance.bank_holidays

        ack_until = now.in_x_hours(n_hours, type_hours.to_s)
      else
        ack_until = Time.at(ack_until.to_i)
      end

      succeeded = []
      failed = []

      alerts.each do |k,v|
        begin
          a = Alert.get!(k.to_i)
        rescue DataMapper::ObjectNotFoundError => ex
          failed << ex
          next
        end

        begin
          a.acknowledge!(@person, ack_until)
          succeeded << a
        rescue StandardError => ex
          logger.error "Caught #{ex.to_s} when trying to save #{a.inspect}"
          logger.debug ex.backtrace.join("\n")
          failed << ex
        end
      end
      #
      # Add the note
      #
      unless note.to_s.empty?
        note = Alert.remove_html(note)
        h = History.new(:alerts => succeeded, :type => "note", :event => session['username']+" noted "+note.to_s)
        logger.debug h.errors unless h.save
      end

      flash["error"] = "Failed to acknowledge #{failed.length} alerts." if failed.length > 0
      flash["notice"] = "Successfully acknowledged #{succeeded.length} alerts" if succeeded.length > 0

      redirect "/alerts/raised"
    end
    
    ######################################################
    # AJAX methods for returning snippets of stuff.
    #

    get '/ajax/time_in_x_hours/:n_hours/:type_hours' do
      content_type :text

      n_hours = params[:n_hours].to_f
      type_hours = params[:type_hours].to_s

      #
      # Sanitise parameters
      #
      n_hours    = ( n_hours > 300 ? 300 : n_hours )
      type_hours = "daytime" unless %w(daytime working wallclock).include?(type_hours)
      now = Time.now
      now.bank_holidays = Server.instance.bank_holidays
      ack_until = now.in_x_hours(n_hours, type_hours)
      
      #
      # Make sure we can't ack longer than a week.
      #
      max_ack   = (Time.now + Configuration.current.max_acknowledgement_time) 
      ack_until = max_ack if ack_until > max_ack

      #
      # Return answer as unix seconds.
      #
      ack_until.to_f.round.to_s
    end

    get '/ajax/time_to_s_human/:seconds' do
      content_type :text
      secs = params[:seconds].to_i
      Time.at(secs).to_s_human
    end

    #
    # This returns an array of 5 numbers.
    #
    get '/ajax/alert_counts' do
      content_type :json
      
      counts = Hash.new{|h,k| h[k] = 0}

      Alert.all_unacknowledged.each{|a| counts[a.level] += 1}

      (AlertGroup::LEVELS.reverse.collect{|l| counts[l]}+
        [Alert.all_acknowledged.length, Alert.all_cleared.length]).to_json
    end

    get '/ajax/alerts_table/:alert_type/:group_by' do
      alerts_table(params)
      haml :_alerts_table, :layout => false
    end

    get '/ajax/alerts_table_alert/:alert_id' do
      content_type "text/html"
      alert = Alert.get(params[:alert_id].to_i)
      return status(404) unless alert

      haml :_alerts_table_alert, :locals => {:alert => alert}, :layout => false
    end
    
    get '/ajax/alerts_table_alert_summary/:alert_id' do
      content_type "text/html"
      alert = Alert.get(params[:alert_id].to_i)
      return status(404) unless alert

      haml :_alerts_table_alert_summary, :locals => {:alert => alert, :row_class => []}, :layout => false
    end
    
    get '/ajax/alerts_table_alert_detail/:alert_id' do
      content_type "text/html"
      alert = Alert.get(params[:alert_id].to_i)
      return status(404) unless alert

      haml :_alerts_table_alert_detail, :locals => {:alert => alert, :row_class => []}, :layout => false
    end


    ####
    #
    # Methods for the individual alerts.
    #

    get '/alert/:id' do
      find_active_alerts
      @alert = Alert.get!(params['id'])

      haml :alert
    end
    
    post '/alert/:id/acknowledge' do
      alert = Alert.get(params[:id])
      
      ack_until  = params[:ack_until].to_i
      n_hours    = params[:n_hours].to_f
      type_hours = params[:type_hours].to_s
      note       = params[:note]       || nil
      
      type_hours = "daytime" unless %w(daytime working wallclock).include?(type_hours)

      if ack_until == 0
        now = Time.now
        now.bank_holidays = Server.instance.bank_holidays

        ack_until = now.in_x_hours(n_hours, type_hours)
      else
        ack_until = Time.at(ack_until)
      end

      alert.acknowledge!(@person, ack_until)
      
      #
      # Add the note
      #
      unless note.to_s.empty?
        h = History.new(:alerts => [alert], :type => "note", :event => session['username']+" noted "+note.to_s)
        logger.debug h.errors unless h.save
      end
      
      flash['notice'] = "Successfully acknowledged alert <em>#{alert.alert_id}</em> from source #{alert.source} until #{alert.will_unacknowledge_at.to_s_human}."
      redirect "/alert/#{alert.id}"
    end

    post '/alert/:id/unacknowledge' do
      alert = Alert.get!(params[:id])
      alert.unacknowledge!
      flash['notice'] = "Successfully raised alert #{alert.alert_id} from source #{alert.source}."
      redirect "/alert/#{alert.id}"
    end

    post '/alert/:id/raise' do
      alert = Alert.get!(params[:id])
      alert.raise!
      flash['notice'] = "Successfully raised alert #{alert.alert_id} from source #{alert.source}."
      redirect "/alert/#{alert.id}"
    end
    
    post '/alert/:id/clear' do
      alert = Alert.get(params[:id])
      alert.clear!
      flash['notice'] = "Successfully cleared alert #{alert.alert_id} from source #{alert.source}."
      redirect "/alert/#{alert.id}"
    end
    
    post '/alert/:id/destroy' do
      alert = Alert.get(params[:id])
      alert.destroy!
      flash['notice'] = "Successfully destroyed alert #{alert.alert_id} from source #{alert.source}."
      redirect "/"
    end

    ########################################################################
    
    get '/preferences' do
      find_active_alerts
      haml :preferences
    end
    
    ########################################################################
   
    get '/events/alert/:id' do
      query = {:alert => {}, :history => {}}
      query[:alert][:id] = params[:id]

      query[:history][:type] = ["update", "notification"]

      @alert  = Alert.get!(params['id'])
      @events = find_events(query)

      haml :events_list
    end

    get '/events/calendar' do
      redirect "/events/calendar/"+Time.now.strftime("%Y-%m")
    end

    get '/events/calendar/:start' do

      #
      # Sort out the parameters
      #

      #
      # Start must be a Monday
      #
      if params[:start] =~ /\A(\d{4,4})-(\d{1,2})/
        @month = Time.local($1.to_i,$2.to_i,1,0,0,0,0)
      else
        t = Time.now
        @month = Time.local(t.year, t.month, 1, 0, 0, 0, 0)
      end

      start  = @month
      finish = start + 31.days

      start  -= (start.wday == 0 ? 6 : (start.wday - 1)).day
      finish -= finish.day if finish.month == @month.month+1
      finish += (finish.wday == 0 ? 0 : (7 - finish.wday)).days

      weeks = ((finish - start)/1.week).ceil
 
      query = {:history => {}}
      query[:history][:created_at.gte] = start
      query[:history][:created_at.lt] = finish

      #
      # Now sort events into a per-week per-weekday array.  Have to use the
      # proc syntax here to prevent an array of pointers being created..?!
      #
      @events = find_events(query)
      @events_by_week = Array.new(weeks){ Array.new(7) { Array.new } }

      @events.each do |event|
        event_week = ((event.created_at - start)/(7.days)).floor
        event_day  = (event.created_at.wday == 0 ? 6 : (event.created_at.wday - 1))
        @events_by_week[event_week] ||= Array.new(7) { Array.new }
        @events_by_week[event_week][event_day] << event
      end

      #
      # Make sure we have all our weeks filled out.
      #
      @events_by_week.each_with_index do |e, i|
        @events_by_week[i] = Array.new(7) { Array.new } if e.nil?
      end

      @today = start
      haml :events_calendar
    end
   
    get '/events/list' do
      redirect "/events/list/"+Time.now.strftime("%Y-%m-%d") 
    end

    get '/events/list/:start' do
      if params[:start] =~ /\A(\d{4,4})-(\d{1,2})-(\d{1,2})\Z/
        start = Time.local($1.to_i,$2.to_i,$3.to_i,0,0,0,0)
      else
        t = Time.now
        start = Time.local(t.year, t.month, t.day, 0,0,0,0)
      end

      finish = start + 1.day + 1.hour

      redirect "/events/list/#{start.strftime("%Y-%m-%d")}/#{finish.strftime("%Y-%m-%d")}"
    end
    
    get '/events/list/:start/:finish' do

      t = Time.now
      if params[:start] =~ /\A(\d{4,4})-(\d{1,2})-(\d{1,2})\Z/
        @start = Time.local($1.to_i,$2.to_i,$3.to_i,0,0,0,0)
      else
        @start = Time.local(t.year, t.month, t.day, 0,0,0,0)
      end
      
      if params[:finish] =~ /\A(\d{4,4})-(\d{1,2})-(\d{1,2})\Z/
        finish = Time.local($1.to_i,$2.to_i,$3.to_i,0,0,0,0)
      else
        t += 1.day + 1.hour
        finish = Time.local(t.year, t.month, t.day, 0,0,0,0)
      end

      query = {:history => {}}
      query[:history][:created_at.gte] = @start
      query[:history][:created_at.lt]  = finish
      
      @events = find_events(query)

      haml :events_list
    end

    get '/search' do
      @alerts = []
      haml :search
    end
 
    get '/search/results' do
      query = {}
      allowed = %w(source subject alert_id summary)

      params.each do |k,v|
        next if v.to_s.empty?
        query[k.to_sym.send("like")] = v.to_s if allowed.include?(k)
      end

      @alerts = Alert.all(query)

      haml :search
    end

    post '/suppress' do
      haml :suppress
    end


    ########################################################################
    
    helpers do
      include Sinatra::Partials
     
      def group_by(things, meth)
        return {} if things.empty?

        raise ArgumentError.new "#{things.first.class} does not respond to #{meth}" unless things.first.respond_to?(meth)
        
        results = Hash.new{|h,k| h[k] = Array.new}

        things.sort.each do |thing|
          results[thing.__send__(meth)] << thing
        end

        results.sort do |a,b|
          [a[1].first, a[0]] <=> [b[1].first, b[0]]
        end
      end

      def alerts_table(params)
        find_active_alerts

        if %w(raised cleared acknowledged).include?(params[:alert_type])
          @alert_type = params[:alert_type]
        else
          @alert_type = "raised"
        end

        if %w(subject source summary id alert_id level).include?(params[:group_by])
          @group_by = params[:group_by]
        else
          @group_by = "subject"
        end

        @title += " Alerts "


        case @alert_type
          when "raised"
            @grouped_alerts = group_by(@alerts_raised, @group_by)
          when "acknowledged"
            @grouped_alerts = group_by(@alerts_ackd, @group_by)
            haml(:alerts)
          else
            haml(:not_implemented)
        end
      end  
 
      def find_active_alerts
        @alerts_raised  = Alert.all_unacknowledged
        @alerts_cleared = Alert.all_cleared
        @alerts_ackd    = Alert.all_acknowledged

        #
        # Tot up the levels for raised alerts.
        #
        counts = Hash.new{|h,k| h[k] = 0}
        @alerts_raised.each{|a| counts[a.level] += 1}
        @title += " [ "+AlertGroup::LEVELS.reverse.collect{|l| counts[l]}.join(" / ") + " ]"
      end

      def find_recent_alerts
        since = params['since'] ? Time.parse(params['since']) : (Time.now-86400)
        @alerts = Alert.all(:updated_at.gt => since, :order => [:raised_at.desc, :cleared_at.desc, :acknowledged_at.desc, :updated_at.desc, ])
      end
      
      def cycle(*list)
        @cycle ||= 0
        @cycle = (@cycle + 1) % list.length
        list[@cycle]
      end

      def find_events(query = Hash.new)

        if params["history"]
          query[:history] ||= Hash.new

          if params["history"]["type"] and !params["history"]["type"].empty?
            query[:history][:type] = params["history"]["type"]
          end
        end

        if !query[:history] or !query[:history][:type]
          query[:history] ||= Hash.new
          query[:history][:type] = "update"

          params["history"] ||= Hash.new
          params["history"]["type"] = "update"
        end

        if params["alert"]
          query[:alert] ||= Hash.new

          if params["alert"]["subject"] and !params["alert"]["subject"].empty?
            query[:alert][:subject.like] = params["alert"]["subject"]
          end

          if params["alert"]["source"] and !params["alert"]["source"].empty?
            query[:alert][:source.like] = params["alert"]["source"]
          end

          if params["alert"]["id"] and !params["alert"]["id"].empty?
            query[:alert][:id] = params["alert"]["id"]
          end
        end

        #
        #
        # THIS IS NOT EAGER LOADING.  But I've no idea how the best way would be to do it.
        #
        alert_histories = AlertHistory.all(query)
  
        histories = alert_histories.history.to_a
        alerts    = alert_histories.alert.to_a


        alert_histories.each do |ah|
          history = histories.find{|h| ah.history_id == h.id}
          alert   = alerts.find{|a| ah.alert_id == a.id}
          next if alert.nil?
          history.add_to_cached_alerts( alert )
        end

        #
        # Present the histories in time-ascending order (which is not the default..)
        #
        histories.reverse
      end

    end
   
    error DataMapper::ObjectNotFoundError do
      status 404
      env['sinatra.error'].message
    end
 
    ########################################################################
    # @see http://stackoverflow.com/questions/2239240/use-rackcommonlogger-in-sinatra
    def logger
      @logger ||= self.class._logger
    end

    def call(env)
      env['rack.errors'] = RackErrorsProxy.new(logger)
      super(env)
    end

  end
end
