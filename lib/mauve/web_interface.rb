# encoding: UTF-8
require 'haml'
require 'redcloth'

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
  
    class PleaseAuthenticate < Exception; end
  
    use Rack::CommonLogger
    use Rack::Chunked
    use Rack::ContentLength
    use Rack::Flash

#    Tilt.register :textile, RedClothTemplate


    # Ugh.. hacky way to dynamically configure the document root.
    set :root, Proc.new{ HTTPServer.instance.document_root }
    set :views, Proc.new{ root && File.join(root, 'views') }
    set :public,  Proc.new{ root && File.join(root, 'static') }
    set :static, true
    set :show_exceptions, true

    logger = Log4r::Logger.new("Mauve::WebInterface")

    set :logging, true
    set :logger, logger
    set :dump_errors, true      # ...will dump errors to the log
    set :raise_errors, false    # ...will not let exceptions out to main program
    set :show_exceptions, false # ...will not show exceptions
    
    ########################################################################
    
    before do
      @title = "Mauve alert panel"
      @person = nil
      #
      # Make sure we're authenticated.
      #

      if session.has_key?('username') and Configuration.current.people.has_key?(session['username'].to_s)
        # 
        # Phew, we're authenticated
        #
        @person = Configuration.current.people[session['username']]

        #
        # A bit wasteful maybe..?
        #
        @alerts_raised  = Alert.all_raised
        @alerts_cleared = Alert.all_cleared
        @alerts_ackd    = Alert.all_acknowledged
        @group_by       = "subject"
      else
        # Uh-oh.. Intruder alert!
        #
        ok_urls = %w(/ /login /logout)

        unless ok_urls.include?(request.path_info) 
          flash['error'] = "You must be logged in to access that page."
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
      if @person
        redirect '/'
      else
        @next_page = params[:next_page] || '/'
        haml :login
      end
    end
 
    post '/login' do
      usr = params['username']
      pwd = params['password']
      next_page = params['next_page']
      #
      # Make sure we don't magically logout automatically :)
      #
      next_page = '/' if next_page == '/logout'

      if auth_helper(usr, pwd)
        session['username'] = usr
        redirect next_page
      else
        flash['error'] = "Access denied."
      end
    end
    
    get '/logout' do
      session.delete('username')
      redirect '/login'
    end
    
    get '/alerts' do 
      redirect '/alerts/raised'
    end

    get '/alerts/:alert_type' do
      redirect "/alerts/#{params[:alert_type]}/subject"
    end

    get '/alerts/:alert_type/:group_by' do 
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

      case @alert_type
        when "raised"
          @grouped_alerts = group_by(@alerts_raised, @group_by)
        when "cleared"
          @grouped_alerts = group_by(@alerts_cleared, @group_by)
        when "acknowledged"
          @grouped_alerts = group_by(@alerts_ackd, @group_by)
      end

      haml(:alerts)
    end
    
    get '/_alert_summary' do
      find_active_alerts; partial("alert_summary")
    end

    get '/_alert_counts' do 
      find_active_alerts; partial("alert_counts")
    end

    get '/_head' do 
      find_active_alerts()
      partial("head")
    end
  
    get '/alert/:id/_detail' do
      content_type "text/html"
      alert = Alert.get(params[:id])

      haml :_detail, :locals => { :alert => alert } unless alert.nil?
    end
    
    get '/alert/:id' do
      find_active_alerts
      @alert = Alert.get(params['id'])
      haml :alert
    end
    
    post '/alert/:id/acknowledge' do
      
      alert = Alert.get(params[:id])
      if alert.acknowledged?
        alert.unacknowledge!
      else
        alert.acknowledge!(@person, 0)
      end
      content_type("application/json")
      alert.to_json
    end
    
    # Note that :until must be in seconds.
    post '/alert/acknowledge/:id/:until' do
      #now = MauveTime.now.to_f

      alert = Alert.get(params[:id])
      alert.acknowledge!(@person, params[:until].to_i())
      
      #print "Acknowledge request was processed in #{MauveTime.now.to_f - now} seconds\n"
      content_type("application/json")
      alert.to_json
    end

    post '/alert/:id/raise' do
      #now = MauveTime.now.to_f
      
      alert = Alert.get(params[:id])
      alert.raise!
      #print "Raise request was processed in #{MauveTime.now.to_f - now} seconds\n"
      content_type("application/json")
      alert.to_json
    end
    
    post '/alert/:id/clear' do
      
      alert = Alert.get(params[:id])
      alert.clear!
      content_type("application/json")
      alert.to_json
    end

    post '/alert/:id/toggleDetailView' do 
      
      alert = Alert.get(params[:id])
      if nil != alert
        id = params[:id].to_i()
        session[:display_alerts][id] = (true == session[:display_alerts][id])? false : true
        content_type("application/json")
        'all is good'.to_json
      end
    end

    post '/alert/fold/:subject' do 
      session[:display_folding][params[:subject]] = (true == session[:display_folding][params[:subject]])? false : true
      content_type("application/json")
      'all is good'.to_json
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

        things.each do |thing|
          results[thing.__send__(meth)] << thing
        end

        results
      end
 
      def find_active_alerts

        # FIXME: make sure alerts only appear once some better way
        #@urgent = AlertGroup.all_alerts_by_level(:urgent)
        #@normal = AlertGroup.all_alerts_by_level(:normal) - @urgent
        #@low = AlertGroup.all_alerts_by_level(:low) - @normal - @urgent
        ook = Alert.get_all()
        @urgent = ook[:urgent]
        @normal = ook[:normal]
        @low = ook[:low]

        # Get groups of alerts and count those acknowledged.
        @grouped_ack_urgent = Hash.new()
        @grouped_ack_normal = Hash.new()
        @grouped_ack_low = Hash.new()
        @grouped_new_urgent = Hash.new()
        @grouped_new_normal = Hash.new()
        @grouped_new_low = Hash.new()
        @count_ack = Hash.new()
        @count_ack[:urgent] = self.group_alerts(@grouped_ack_urgent, 
                                                @grouped_new_urgent,
                                                @urgent)
        @count_ack[:normal] = self.group_alerts(@grouped_ack_normal,
                                                @grouped_new_normal,
                                                @normal)
        @count_ack[:low] = self.group_alerts(@grouped_ack_low,
                                             @grouped_new_low,
                                             @low)
        @grouped_ack = Hash.new()
        @grouped_new = Hash.new()
        @grouped_ack_urgent.each_pair {|k,v| @grouped_ack[k] = v}
        @grouped_ack_normal.each_pair {|k,v| @grouped_ack[k] = v}
        @grouped_ack_low.each_pair {|k,v| @grouped_ack[k] = v}
        @grouped_new_urgent.each_pair {|k,v| @grouped_new[k] = v}
        @grouped_new_normal.each_pair {|k,v| @grouped_new[k] = v}
        @grouped_new_low.each_pair {|k,v| @grouped_new[k] = v}
      end
      
      ## Fill two hashs with alerts that are acknowledged or not.
      # @param [Hash] ack Acknowledge hash.
      # @param [Hash] new Unacknowledged (aka new) hash.
      # @param [List] list List of alerts.
      # @return [Fixnum] The count of acknowledged alerts.
      def group_alerts(ack, new, list)
        count = 0
        list.each do |alert| 
          #key = alert.source + '::' + alert.subject
          key = alert.subject
          if true == alert.acknowledged?
            count += 1
            ack[key] = Array.new() if false == ack.has_key?(key)
            ack[key] << alert
          else
            new[key] = Array.new() if false == new.has_key?(key)
            new[key] << alert
          end
          if false == session[:display_alerts].has_key?(alert.id)
            session[:display_alerts][alert.id] = false
          end
          if false == session[:display_folding].has_key?(key)
            session[:display_folding][key] = false 
          end
          #session[:display_alerts][alert.id] = true if false == session[:display_alerts].has_key?(alert.id)
          #session[:display_folding][key] = true if false == session[:display_folding].has_key?(key)
          new.each_key {|k| new[k].sort!{|a,b| a.summary <=> b.summary} }
          ack.each_key {|k| ack[k].sort!{|a,b| a.summary <=> b.summary} }
        end
        return count
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
    
    ########################################################################
    
    error PleaseAuthenticate do
      status 403
      session[:display_alerts] = Hash.new()
      session[:display_folding] = Hash.new()
    end
    
    ########################################################################
    # @see http://stackoverflow.com/questions/2239240/use-rackcommonlogger-in-sinatra
    def call(env)
      if true == @logger.nil?
        @logger = Log4r::Logger.new("Mauve::Rack")
      end
      env['rack.errors'] = RackErrorsProxy.new(@logger)
      super(env)
    end
    
  end

end
