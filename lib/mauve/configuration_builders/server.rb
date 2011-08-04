# encoding: UTF-8
require 'mauve/server'
require 'mauve/configuration_builder'

module Mauve
  module ConfigurationBuilders

    class HTTPServer < ObjectBuilder
      is_attribute "port"
      is_attribute "ip"
      is_attribute "document_root"
      is_attribute "session_secret"
      is_attribute "base_url"

      def builder_setup
        @result = Mauve::HTTPServer.instance
      end
    end

    class UDPServer < ObjectBuilder
      is_attribute "port"
      is_attribute "ip"
      is_attribute "poll_every"
    
      def builder_setup
        @result = Mauve::UDPServer.instance
      end
    end

    class Processor < ObjectBuilder
      is_attribute "poll_every"
      is_attribute "transmission_cache_expire_time"

      def builder_setup
        @result = Mauve::Processor.instance
      end
    end

    class Timer < ObjectBuilder
      is_attribute "poll_every"

      def builder_setup
        @result = Mauve::Timer.instance
      end
    end

    class Notifier < ObjectBuilder
      is_attribute "poll_every"

      def builder_setup
        @result = Mauve::Notifier.instance
      end
    end
 
    class Heartbeat < ObjectBuilder
      is_attribute "destination"
      is_attribute "detail"
      is_attribute "summary"
      is_attribute "raise_after"
      is_attribute "send_every"
    
      def builder_setup
        @result = Mauve::Heartbeat.instance
      end
    end

    class Pop3Server < ObjectBuilder
      is_attribute "ip"
      is_attribute "port"

      def builder_setup
        @result = Mauve::Pop3Server.instance
      end
    end

    class Server < ObjectBuilder
      #
      # Set up second-level builders
      #
      is_builder "web_interface", HTTPServer
      is_builder "listener",      UDPServer
      is_builder "processor",     Processor
      is_builder "timer",         Timer
      is_builder "notifier",      Notifier
      is_builder "heartbeat",     Heartbeat
      is_builder "pop3_server",   Pop3Server

      is_attribute "hostname"
      is_attribute "database"
      is_attribute "initial_sleep"
   
      def builder_setup
        @result = Mauve::Server.instance
      end
    end
  end

  #
  # Add server to our top-level config builder
  #
  class ConfigurationBuilder < ObjectBuilder

    is_builder "server", ConfigurationBuilders::Server

    def created_server(server)
      raise BuildError.new("Only one 'server' clause can be specified") if @result.server
      @result.server = server
    end

  end

end
