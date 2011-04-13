# encoding: UTF-8
require 'sinatra/base'
require 'sinatra-partials'
require 'haml'
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
  
    use Rack::Session::Cookie, :expire_after => 604800 # 7 days in seconds

    enable :sessions

    use Rack::Flash
    
    set :root, "/usr/share/mauve"
    set :views, "#{root}/views"
    set :public, "#{root}/static"
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
      @person = Configuration.current.people[session['username']]
      @title = "Mauve alert panel"
    end
    
    get '/' do
      redirect '/alerts'
    end
    
    ########################################################################
    
    ## Checks the identity of the person via a password.
    #
    # The password can be either the SSO or a local one defined 
    # in the configuration file.
    #
    post '/login' do
      usr = params['username']
      pwd = params['password']
      ret_sso = helper_auth_SSO(usr, pwd)
      ret_loc = helper_auth_local(usr, pwd)
      if "success" == ret_sso or "success" == ret_loc
        session['username'] = usr
      else
        flash['error'] =<<__MSG
<hr /> <img src="/images/error.png" /> <br />
ACCESS DENIED  <br />
#{ret_sso} <br />
#{ret_loc} <hr />
__MSG
      end
      redirect '/alerts'
    end
    
    get '/logout' do
      session.delete('username')
      redirect '/alerts'
    end
    
    get '/alerts' do 
      #now = MauveTime.now.to_f
      please_authenticate()
      find_active_alerts()
      #pp MauveTime.now.to_f - now
      haml(:alerts2)
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
  
    get '/alert/:id/detail' do
      please_authenticate
    
      content_type("text/html") # I think
      Alert.get(params[:id]).detail
    end
    
    get '/alert/:id' do
      please_authenticate
      find_active_alerts
      @alert = Alert.get(params['id'])
      haml :alert
    end
    
    post '/alert/:id/acknowledge' do
      please_authenticate
      
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
      please_authenticate

      alert = Alert.get(params[:id])
      alert.acknowledge!(@person, params[:until].to_i())
      
      #print "Acknowledge request was processed in #{MauveTime.now.to_f - now} seconds\n"
      content_type("application/json")
      alert.to_json
    end

    post '/alert/:id/raise' do
      #now = MauveTime.now.to_f
      please_authenticate
      
      alert = Alert.get(params[:id])
      alert.raise!
      #print "Raise request was processed in #{MauveTime.now.to_f - now} seconds\n"
      content_type("application/json")
      alert.to_json
    end
    
    post '/alert/:id/clear' do
      please_authenticate
      
      alert = Alert.get(params[:id])
      alert.clear!
      content_type("application/json")
      alert.to_json
    end

    post '/alert/:id/toggleDetailView' do 
      please_authenticate
      
      alert = Alert.get(params[:id])
      if nil != alert
        id = params[:id].to_i()
        session[:display_alerts][id] = (true == session[:display_alerts][id])? false : true
        content_type("application/json")
        'all is good'.to_json
      end
    end

    post '/alert/fold/:subject' do 
      please_authenticate
      
      session[:display_folding][params[:subject]] = (true == session[:display_folding][params[:subject]])? false : true
      content_type("application/json")
      'all is good'.to_json
    end

    ########################################################################
    
    get '/preferences' do
      please_authenticate
      find_active_alerts
      haml :preferences
    end
    
    ########################################################################
    
    get '/events' do
      please_authenticate
      find_active_alerts
      find_recent_alerts
      haml :events
    end
    
    ########################################################################
    
    helpers do
      include Sinatra::Partials
      
      def please_authenticate
        raise PleaseAuthenticate.new unless @person
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
      def helper_auth_SSO (usr, pwd)
        auth = AuthSourceBytemark.new()
        begin
          return "success" if true == auth.authenticate(usr,pwd)
          return "SSO did not regcognise your login/password combination."
        rescue ArgumentError => ex
          return "SSO argument error: #{ex.message}"
        rescue => ex
          return "SSO generic error: #{ex.message}"
        end
      end

      ## Test for authentication with configuration file parameter.
      #
      def helper_auth_local (usr, pwd)
        person = Configuration.current.people[params['username']]
        return "I did not recognise your local login details." if !person
        return "I did not recognise your local password." if Digest::SHA1.hexdigest(params['password']) != person.password
        return "success"
      end

    end
    
    ########################################################################
    
    error PleaseAuthenticate do
      status 403
      session[:display_alerts] = Hash.new()
      session[:display_folding] = Hash.new()
      haml :please_authenticate
    end
    
    ########################################################################
    # @see http://stackoverflow.com/questions/2239240/use-rackcommonlogger-in-sinatra
    def call(env)
      if true == @logger.nil?
        @logger = Log4r::Logger.new("mauve::Rack")
      end
      env['rack.errors'] = RackErrorsProxy.new(@logger)
      super(env)
    end
    
  end

end
