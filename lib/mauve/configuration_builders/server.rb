# encoding: UTF-8
require 'mauve/server'
require 'mauve/configuration_builder'

module Mauve
  module ConfigurationBuilders

    #
    # This is the HTTP server
    #
    class HTTPServer < ObjectBuilder
      # The port the http server listens on
      is_attribute "port"
      # The IP address the http server listens on.  IPv6 is *NOT* OK.
      is_attribute "ip"
      # Where all the templates are kept
      is_attribute "document_root"
      # The secret for the cookies
      is_attribute "session_secret"
      # The base URL of the server.
      is_attribute "base_url"

      # Sets up a Mauve::HTTPServer singleton as the result
      #
      # @return [Mauve::HTTPServer]
      def builder_setup
        @result = Mauve::HTTPServer.instance
      end
    end

    #
    # This is the UDP server.
    #
    class UDPServer < ObjectBuilder
      # This is the port the server listens on
      is_attribute "port"
      # This is the IP address the server listens on.  IPv6 is OK! e.g. [::] for  all addresses
      is_attribute "ip"
      # This is the sleep interval for the UDP server.
      is_attribute "poll_every"
    
      # Sets up a Mauve::UDPServer singleton as the result
      #
      # @return [Mauve::UDPServer]
      def builder_setup
        @result = Mauve::UDPServer.instance
      end
    end

    #
    # This is the thread that pulls packets from the queue for processing.
    #
    class Processor < ObjectBuilder
      # This is the interval between polls of the packet queue.
      is_attribute "poll_every"
      # This is the timeout for the transmission cache, which allows duplicate packets to be discarded.
      is_attribute "transmission_cache_expire_time"

      # Sets up a Mauve::Processor singleton as the result
      #
      # @return [Mauve::Processor]
      def builder_setup
        @result = Mauve::Processor.instance
      end
    end

    class Notifier < ObjectBuilder
      #
      # This is the interval at which the notification queue is polled for new
      # notifications to be sent.  This will not have any rate-limiting effect.
      #
      is_attribute "poll_every"

      # Sets up a Mauve::Notifier singleton as the result
      #
      # @return [Mauve::Notifier]
      def builder_setup
        @result = Mauve::Notifier.instance
      end
    end
 
    #
    # This sends a mauve heartbeat to another Mauve instance elsewhere
    #
    class Heartbeat < ObjectBuilder
      #
      # The destination for the heartbeat
      #
      is_attribute "destination"

      #
      # The detail field for the heartbeat
      #
      is_attribute "detail"

      #
      # The summary field for the heartbeat.
      #
      is_attribute "summary"

      #
      # How long to raise an alert after the last heartbeat.
      #
      is_attribute "raise_after"

      #
      # The interval between heartbeats
      #
      is_attribute "send_every"

      # Sets up a Mauve::Heartbeat singleton as the result
      #
      # @return [Mauve::Heartbeat]
      def builder_setup
        @result = Mauve::Heartbeat.instance
      end
    end

    class Pop3Server < ObjectBuilder
      #
      # The IP adderess the Pop3 server listens on
      #
      is_attribute "ip"

      #
      # The POP3 server port
      #
      is_attribute "port"

      # Sets up a Mauve::Pop3Server singleton as the result
      #
      # @return [Mauve::Pop3Server]
      def builder_setup
        @result = Mauve::Pop3Server.instance
      end
    end

    #
    # This is the main Server singleton.
    #
    class Server < ObjectBuilder
      #
      # Set up second-level builders
      #
      is_builder "web_interface", HTTPServer
      is_builder "listener",      UDPServer
      is_builder "processor",     Processor
      is_builder "notifier",      Notifier
      is_builder "heartbeat",     Heartbeat
      is_builder "pop3_server",   Pop3Server

      #
      # The name of the server this instance of Mauve is running on
      #
      is_attribute "hostname"

      #
      # The database definition
      #
      is_attribute "database"

      #
      # The period of sleep during which no heartbeats are raised.
      #
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

    # This is called once the server object has been created.
    #
    # @raise [SyntaxError] if more than one server clause has been defined.
    #
    def created_server(server)
      raise SyntaxError.new("Only one 'server' clause can be specified") if @result.server
      @result.server = server
    end

  end

end
