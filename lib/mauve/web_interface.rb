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
    set :public_folder,  Proc.new{ root && File.join(root, 'static') }
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
      # Set our alert counts hash up, needed by the navbar.
      #
      @alert_counts = Hash.new{|h,k| h[k] = 0}

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

      @alert_type     = params[:alert_type] == "acknowledged" ? "acknowledged" : "raised"
      @alert_counts   = alert_counts(true)
      @grouped_alerts = alerts_table(@alert_type, params[:group_by])
      @title += " #{@alert_type.capitalize}: "

      @permitted_actions = []
      @permitted_actions << "clear"

      unless @alert_type == "acknowledged"
        @permitted_actions << "acknowledge" 
      else 
        @permitted_actions << "unacknowledge"
      end

      #
      # Always allow suppress and unsuppress
      #
      @permitted_actions << "suppress" 
      @permitted_actions << "unsuppress"

      haml(:alerts)
    end

    post '/alerts' do
      #
      # TODO: error check inputs
      #
      # ack_until is in milliseconds!
      function   = params[:function]    || "acknowledge"
      ack_until  = params[:ack_until]
      n_hours    = params[:n_hours]    || 2
      type_hours = params[:type_hours] || "daytime"
      alerts     = params[:alerts]     || []
      note       = params[:note]       || nil

      n_hours = (n_hours.to_f > 188 ? 188 : n_hours.to_f)
      type_hours = "daytime" unless %w(daytime working wallclock).include?(type_hours)
      function   = "acknowledge" unless %w(raise clear acknowledge unacknowledge unsuppress suppress).include?(function)

      if %w(suppress acknowledge).include?(function)
        if ack_until.to_s.empty?
          now = Time.now
          ack_until = now.in_x_hours(n_hours, type_hours.to_s)
        else
          ack_until = Time.at(ack_until.to_i)
        end
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
          result = case function
            when "raise"
              a.raise!
            when "clear"
              a.clear!
            when "acknowledge"
              a.acknowledge!(@person, ack_until)
            when "unacknowledge"
              a.unacknowledge!
            when "suppress"
              a.suppress_until = ack_until
              a.save
            when "unsuppress"
              a.suppress_until = nil
              a.save
          end
          if result
            succeeded << a
          else
            failed << a
          end
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
        h = History.new(:alerts => succeeded, :type => "note", :event => note.to_s, :user => session['username'])
        logger.debug h.errors unless h.save
      end

      flash["error"] = "Failed to #{function} #{failed.length} alerts." if failed.length > 0

      redirect back
    end
    
    ######################################################
    # AJAX methods for returning snippets of stuff.
    #

    get '/ajax/time_in_x_hours/:n_hours/:type_hours' do
      content_type "application/json"

      n_hours = params[:n_hours].to_f
      type_hours = params[:type_hours].to_s

      now = Time.now
      max_ack   = (Time.now + Configuration.current.max_acknowledgement_time) 
      
      #
      # Make sure we can't ack longer than the configuration allows. 
      #
      if (n_hours * 3600.0).to_i > Configuration.current.max_acknowledgement_time
        ack_until = max_ack
      else      
        type_hours = "daytime" unless %w(daytime working wallclock).include?(type_hours)
        ack_until = now.in_x_hours(n_hours, type_hours)
        ack_until = max_ack if ack_until > max_ack
      end
      
      #
      # Return answer as unix seconds.
      #
      "{ \"time\" : #{ack_until.to_f.round}, \"string\" : \"#{ack_until.to_s_human}\" }"
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
      
      alert_counts = alert_counts(true)

      [:urgent, :normal, :low, :acknowledged, :cleared].collect{|k| alert_counts[k]}.to_json
    end

    get '/ajax/alerts_table/:alert_type/:group_by' do
      return haml(:not_implemented, :layout => false) unless %w(raised acknowledged).include?(params[:alert_type])

      @alert_type     = params[:alert_type] == "acknowledged" ? "acknowledged" : "raised"
      @grouped_alerts = alerts_table(@alert_type, params[:group_by])
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
      @alert = Alert.get!(params['id'])
      @alert_counts = alert_counts(false)

      @permitted_actions = []
      unless @alert.raised?
        @permitted_actions << "raise"
      else
        @permitted_actions << "clear"

        unless @alert.acknowledged?
          @permitted_actions << "acknowledge" 
        else 
          @permitted_actions << "unacknowledge"
        end
      end

      unless @alert.suppressed?
        @permitted_actions << "suppress" 
      else
        @permitted_actions << "unsuppress"
      end
      

      haml :alert
    end
    
    post '/alert/:id' do
      alert = Alert.get(params[:id])
      
      function   = params[:function]
      ack_until  = params[:ack_until].to_i
      n_hours    = params[:n_hours].to_f
      type_hours = params[:type_hours].to_s
      note       = params[:note]       || nil
      
      type_hours = "daytime" unless %w(daytime working wallclock).include?(type_hours)
      function   = "acknowledge" unless %w(raise clear acknowledge unacknowledge suppress unsuppress).include?(function)

      if %w(suppress acknowledge).include?(function)
        if ack_until == 0
          now = Time.now
          ack_until = now.in_x_hours(n_hours, type_hours)
        else
          ack_until = Time.at(ack_until)
        end
      end

      result = case function
        when "raise"
          alert.raise!
        when "clear"
          alert.clear!
        when "acknowledge"
          alert.acknowledge!(@person, ack_until)
        when "unacknowledge"
          alert.unacknowledge!
        when "suppress"
          alert.suppress_until = ack_until
          alert.save
        when "unsuppress"
          alert.suppress_until = nil
          alert.save
      end

       if result
        #
        # Add the note
        #
        unless note.to_s.empty?
          h = History.new(:alerts => [alert], :type => "note", :event => note.to_s, :user => session['username'])
          logger.debug h.errors unless h.save
        end
      
      else
        flash['warning'] = "Failed to #{function} alert <em>#{alert.alert_id}</em> from source #{alert.source}."
      end

      redirect back
    end

    ########################################################################
    
    get '/events/alert/:id' do
      query = {:alert => {}, :history => {}}
      query[:alert][:id] = params[:id]

      query[:history][:type]  = ["update", "notification"]
      query[:history][:order] = [:created_at.asc]

      @alert  = Alert.get!(params['id'])
      @title += " Events: Alert #{@alert.alert_id} from #{@alert.source}"
      @alert_counts = alert_counts(false)
      @events =  AlertHistory.all(formulate_events_query(query))

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
        @month = Date.new($1.to_i, $2.to_i, 1)
      else
        t = Date.today
        @month = Date.new(t.year, t.month, 1)
      end

      start  = @month
      finish = (start >> 1) 

      start  -= (start.wday == 0 ? 6 : (start.wday - 1))
      finish -= finish.day if finish.month == @month.month+1
      finish += (finish.wday == 0 ? 0 : (7 - finish.wday))

      weeks = ((finish - start)/7).ceil

      #
      # Now sort events into a per-week per-weekday array.  Have to use the
      # proc syntax here to prevent an array of pointers being created..?!
      #
      @events_by_week = Array.new(weeks){ Array.new(7) { Array.new } }
      today = start
      while today <= finish
        tomorrow = (today + 1)

        query = {:history => {}}
        query[:history][:created_at.gte] = Time.local(today.year, today.month, today.day, 0, 0, 0)
        query[:history][:created_at.lt]  = Time.local(tomorrow.year, tomorrow.month, tomorrow.day, 0, 0, 0)
        query[:history][:order]          = [:created_at.asc]

        events =  AlertHistory.all(formulate_events_query(query))
        event_week = ((today - start)/7).floor
        event_day  = (today.wday == 0 ? 6 : (today.wday - 1))

        @events_by_week[event_week] ||= Array.new(7) { Array.new }
        @events_by_week[event_week][event_day] = events
        today = tomorrow
      end

      @today = start
      @title += " Events" 
      @alert_counts = alert_counts(false)

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
      query[:history][:order]          = [:created_at.asc]
      
      @events =  AlertHistory.all(formulate_events_query(query))
      @alert_counts = alert_counts(false)

      haml :events_list
    end

    get '/search' do
      @alerts = []
      @alert_counts = alert_counts(false)
      @q = params[:q] || nil
      @title += " Search:"
      @min_length = 3

      @q = @q.to_s.strip unless @q.nil?

      unless @q.nil? or @q.length < @min_length
        alerts = []
        %w(source subject alert_id summary).each do |field|
           alerts += Alert.all(field.to_sym.send("like") =>  "%#{@q}%")
        end

        @alerts = alerts.sort.uniq
      end

      @permitted_actions = []
      @permitted_actions << "clear" if @alerts.any?{|a| a.raised?}
      @permitted_actions << "raise" if @alerts.any?{|a| a.cleared?}
      @permitted_actions << "acknowledge" if @alerts.any?{|a| !a.acknowledged?}
      @permitted_actions << "unacknowledge" if @alerts.any?{|a| a.acknowledged?}
      @permitted_actions << "unsuppress" if @alerts.any?{|a| a.suppressed? }
      @permitted_actions << "suppress" if @alerts.any?{|a| !a.suppressed? }

      haml :search
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

      def alerts_table(alert_type, group_by)
        unless %w(subject source summary id alert_id level).include?(group_by)
          group_by = "subject"
        end

        case alert_type
          when "raised"
            alerts = Alert.all_unacknowledged
            group_by(alerts, group_by)
          when "acknowledged"
            alerts = Alert.all_acknowledged
            group_by(alerts, group_by)
          else
            []
        end
      end  
 
      def cycle(*list)
        @cycle ||= 0
        @cycle = (@cycle + 1) % list.length
        list[@cycle]
      end

      #
      # Returns a hash which contains the counts of:
      #
      #   * all raised alerts (:raised)
      #   * all cleared alerts (:cleared)
      #   * all raised and acknowledged alerts (:acknowledged)
      #   * all raised and unacknowledged alerts (:unacknowledged)
      #
      # If by_level is true, then alerts are counted up by level too.
      #
      #   * all raised and unacknowledged alerts by level (:urgent, :normal, :low)
      #
      #
      def alert_counts(by_level = false)
        counts = Hash.new
        counts[:raised] = Alert.all_raised.count
        counts[:cleared] = Alert.all.count - counts[:raised]
        counts[:acknowledged] = Alert.all_acknowledged.count
        counts[:unacknowledged] = counts[:raised] - counts[:acknowledged]

        if by_level
          #
          # Now we need to work out the levels
          #
          [:urgent, :normal, :low].each{|k| counts[k] = 0}
          Alert.all_unacknowledged.each do |a| 
            counts[a.level] += 1
          end
        end

        counts
      end


      def formulate_events_query(query = Hash.new)

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

        query
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
