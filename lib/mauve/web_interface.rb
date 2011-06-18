# encoding: UTF-8
require 'haml'
require 'redcloth'
require 'json'

require 'sinatra/tilt'
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

        unless ok_urls.include?(request.path_info) 
          flash['error'] = "You must be logged in to access that page."
          status 403
          redirect "/login?next_page=#{request.path_info}"
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
        @next_page = params[:next_page] || '/'
        haml :login
      end
    end
 
    post '/login' do
      usr = params['username'].to_s
      pwd = params['password'].to_s
      next_page = params['next_page'].to_s
      
      #
      # Make sure we don't magically logout automatically :)
      #
      next_page = '/' if next_page == '/logout'

      if auth_helper(usr, pwd)
        session['username'] = usr
        redirect next_page
      else
        flash['error'] = "You must be logged in to access that page."
        redirect "/login?next_page=#{next_page}"
      end
    end
    
    get '/logout' do
      session.delete('username')
      flash['error'] = "You have logged out!"
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
      type_hours = params[:type_hours] || "daylight"
      alerts     = params[:alerts]     || []

      n_hours = (n_hours.to_i > 188 ? 188 : n_hours.to_i)

      if ack_until.to_s.empty?
        ack_until = Time.now.in_x_hours(n_hours, type_hours.to_s)
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
        end

        begin
          a.acknowledge!(@person, ack_until)
          succeeded << a
        rescue StandardError => ex
          failed << ex
        end
      end

      flash["errors"] = "Failed to acknowledge #{failed.length} alerts." if failed.length > 0
      flash["notice"] = "Successfully acknowledged #{succeeded.length} alerts" if succeeded.length > 0

      redirect "/alerts/raised"
    end
    
    ######################################################
    # AJAX methods for returning snippets of stuff.
    #

    get '/ajax/time_in_x_hours/:n_hours/:type_hours' do
      content_type :text

      n_hours = params[:n_hours].to_i
      type_hours = params[:type_hours].to_s

      #
      # Sanitise parameters
      #
      n_hours    = ( n_hours > 300 ? 300 : n_hours )
      type_hours = "daytime" unless %w(daytime working wallclock).include?(type_hours)
      ack_until = Time.now.in_x_hours(n_hours, type_hours)
      
      #
      # Make sure we can't ack longer than a week.
      #
      max_ack   = (Time.now + 86400*8)
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

      Alert.all_raised.each{|a| counts[a.level] += 1}

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
      n_hours    = params[:n_hours].to_i
      type_hours = params[:type_hours].to_s
      
      if ack_until == 0
        ack_until = Time.now.in_x_hours(n_hours, type_hours)
      else
        ack_until = Time.at(ack_until)
      end

      alert.acknowledge!(@person, ack_until)
      
      flash['notice'] = "Successfully acknowleged alert <em>#{alert.alert_id}</em> from source #{alert.source}."
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
    
    get '/events' do
      find_active_alerts
      find_recent_alerts
      haml :events
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
        @alerts_raised  = Alert.all_raised
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
        since = params['since'] ? MauveTime.parse(params['since']) : (MauveTime.now-86400)
        @alerts = Alert.all(:updated_at.gt => since, :order => [:raised_at.desc, :cleared_at.desc, :acknowledged_at.desc, :updated_at.desc, ])
      end
      
      def cycle(*list)
        @cycle ||= 0
        @cycle = (@cycle + 1) % list.length
        list[@cycle]
      end

      ## Test for authentication with SSO.
      #
      def auth_helper (usr, pwd)
        # First try Bytemark
        #
        auth = AuthBytemark.new()
        result = begin
          auth.authenticate(usr,pwd)
        rescue Exception => ex
          @logger.debug "Caught exception during Bytemark auth for #{usr} (#{ex.to_s})"
          false
        end

        if true == result
          return true
        else
          @logger.debug "Bytemark authentication failed for #{usr}"
        end

        # 
        # OK now try local auth
        #
        result = begin
          if Configuration.current.people.has_key?(usr)
            Digest::SHA1.hexdigest(params['password']) == Configuration.current.people[usr].password
          end
        rescue Exception => ex
          @logger.debug "Caught exception during local auth for #{usr} (#{ex.to_s})"
          false
        end

        if true == result
          return true
        else
          @logger.debug "Local authentication failed for #{usr}"
        end

        #
        # Rate limit logins.
        #
        sleep 5
        false
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
