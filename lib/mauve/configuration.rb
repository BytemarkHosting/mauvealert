# encoding: UTF-8
require 'object_builder'
require 'mauve/server'
require 'mauve/web_interface'
require 'mauve/person'
require 'mauve/notification'
require 'mauve/alert_group'
require 'mauve/people_list'
require 'mauve/source_list'

# Seconds, minutes, hours, days, and weeks... More than that, we 
# really should not need it.
class Integer
  def seconds; self; end
  def minutes; self*60; end
  def hours; self*3600; end
  def days; self*86400; end
  def weeks; self*604800; end
  alias_method :day, :days
  alias_method :hour, :hours
  alias_method :minute, :minutes
  alias_method :week, :weeks
end

module Mauve

  ## Configuration object for Mauve.
  #
  #
  # @TODO Write some more documentation. This is woefully inadequate.
  #
  #
  # == How to add a new class to the configuration?
  #
  # - Add a method to ConfigurationBuilder such that your new object
  # maybe created.  Call it created_NEW_OBJ.
  #
  # - Create a new class inheriting from ObjectBuilder with at least a 
  # builder_setup() method.  This should create the new object you want.
  #
  # - Define attributes for the new class are defined as "is_attribute". 
  #
  # - Methods for the new class are defined as methods or missing_method
  # depending on what one wishes to do.  Remember to define a method
  # with "instance_eval(&block)" if you want to call said block within
  # the new class.
  #
  # - Add a "is_builder "<name>", BuilderCLASS" clause in the
  #   ConfigurationBuilder class.
  #
  # That should be it.
  #
  # @author Matthew Bloch, Yann Golanski
  class Configuration

    class << self
      attr_accessor :current
    end
    
    attr_accessor :server
    attr_accessor :last_alert_group
    attr_reader :notification_methods
    attr_reader :people
    attr_reader :alert_groups
    attr_reader :people_lists
    attr_reader :source_lists
    attr_reader :logger
    
    def initialize
      @notification_methods = {}
      @people = {}
      @people_lists = {}
      @alert_groups = []
      @source_lists = SourceList.new()
      @logger = Log4r::Logger.new("Mauve")

    end
    
    def close
      server.close
    end

  end

  class LoggerOutputterBuilder < ObjectBuilder

    def builder_setup(outputter)
      @outputter = outputter.capitalize+"Outputter"

      begin
        Log4r.const_get(@outputter)
      rescue
        require "log4r/outputter/#{@outputter.downcase}"
      end

      @args = {}
    end

    def result
      @result ||= Log4r.const_get(@outputter).new("Mauve", @args)
    end

    def format(f)
      result.formatter = Log4r::PatternFormatter.new(:pattern => f)
    end

    def method_missing(name, value=nil)
      if value.nil?
        result.send(name.to_sym)
      else
        @args[name.to_sym] = value
      end
    end

  end
  
  class LoggerBuilder < ObjectBuilder

    is_builder "outputter", LoggerOutputterBuilder

    def builder_setup
      logger = Log4r::Logger.new("Mauve")
      @default_format = nil
      @default_level  = Log4r::RootLogger.instance.level
    end

    def result
      @result = Log4r::Logger['Mauve']
    end

    def default_format(f)
      @default_formatter = Log4r::PatternFormatter.new(:pattern => f)
      #
      # Set all current outputters
      #
      result.outputters.each do |o|
        o.formatter = @default_formatter if o.formatter.is_a?(Log4r::DefaultFormatter)
      end
    end

    def default_level(l)
      if Log4r::Log4rTools.valid_level?(l)
        @default_level = l
      else
        raise "Bad default level set for the logger #{l}.inspect"
      end

      result.outputters.each do |o|
        o.level = @default_level if o.level == Log4r::RootLogger.instance.level
      end
    end

    def created_outputter(outputter)
      #
      # Set the formatter and level for any newly created outputters
      #
      if @default_formatter
        outputter.formatter = @default_formatter if outputter.formatter.is_a?(Log4r::DefaultFormatter)
      end

      if @default_level
        outputter.level = @default_level if outputter.level == Log4r::RootLogger.instance.level
      end

      result.outputters << outputter
    end

  end

  class ProcessorBuilder < ObjectBuilder
    is_attribute "sleep_interval"

    def builder_setup
      @result = Processor.instance
    end

    def method_missing(name, value)
      @args[name] = value
    end
  end

  class UDPServerBuilder < ObjectBuilder
    is_attribute "port"
    is_attribute "ip"
    is_attribute "sleep_interval"
    
    def builder_setup
      @result = UDPServer.instance
    end

    def method_missing(name, value)
      @args[name] = value
    end
  end

  class TimerBuilder < ObjectBuilder
    is_attribute "sleep_interval"
    
    def builder_setup
      @result = Timer.instance
    end

    def method_missing(name, value)
      @args[name] = value
    end


  end

  class HTTPServerBuilder < ObjectBuilder

    is_attribute "port"
    is_attribute "ip"
    is_attribute "document_root"
    
    def builder_setup
      @result = HTTPServer.instance
    end

    def method_missing(name, value)
      @args[name] = value
    end

  end
  
  class NotifierBuilder < ObjectBuilder
    is_attribute "sleep_interval"

    def builder_setup
      @result = Notifier.instance
    end

    def method_missing(name, value)
      @args[name] = value
    end

  end

  class ServerBuilder < ObjectBuilder

    is_builder "web_interface", HTTPServerBuilder
    is_builder "listener",      UDPServerBuilder
    is_builder "processor",     ProcessorBuilder
    is_builder "timer",         TimerBuilder
    is_builder "notifier",      NotifierBuilder
    
    def builder_setup
      @args = {}
    end
    
    def result
      @result = Mauve::Server.instance
      @result.configure(@args)
      @result.web_interface = @web_interface
      @result
    end
    
    def method_missing(name, value)
      @args[name] = value
    end
    
    def created_web_interface(web_interface)
      @web_interface = web_interface
    end

    def created_listener(listener)
      @listener = listener
    end

    def created_processor(processor)
      @processor = processor
    end

    def created_notifier(notifier)
      @notifier = notifier
    end
  end

  class NotificationMethodBuilder < ObjectBuilder

    def builder_setup(name)
      @notification_type = name.capitalize
      @name = name
      provider("Default")
    end


    def provider(name)
      notifiers_base = Mauve::Notifiers
      notifiers_type = notifiers_base.const_get(@notification_type)
      @provider_class = notifiers_type.const_get(name)
    end
    
    def result
      @result ||= @provider_class.new(@name)
    end
    
    def method_missing(name, value=nil)
      if value
        result.send("#{name}=".to_sym, value)
      else
        result.send(name.to_sym)
      end
    end

  end

  class PersonBuilder < ObjectBuilder

    def builder_setup(username)
      @result = Person.new(username)
    end

    is_block_attribute "urgent"
    is_block_attribute "normal"
    is_block_attribute "low"
    
    def all(&block); urgent(&block); normal(&block); low(&block); end

    def password (pwd)
      @result.password = pwd.to_s
    end

    def holiday_url (url)
      @result.holiday_url = url
    end
    
    def suppress_notifications_after(h)
      raise ArgumentError.new("notification_threshold must be specified as e.g. (10 => 1.minute)") unless
        h.kind_of?(Hash) && h.keys[0].kind_of?(Integer) && h.values[0].kind_of?(Integer)
      @result.notification_thresholds[h.values[0]] = Array.new(h.keys[0])
    end

  end

  class NotificationBuilder < ObjectBuilder

    def builder_setup(*who)
      who = who.map do |username|
        #raise BuildException.new("You haven't declared who #{username} is") unless
        #  @context.people[username]
        #@context.people[username]
        if @context.people[username] 
          @context.people[username]
        elsif @context.people_lists[username]
          @context.people_lists[username]
        else
          raise BuildException.new("You have not declared who #{username} is")
        end
      end
      @result = Notification.new(who, @context.last_alert_group.level)
    end
    
    is_attribute "every"
    is_block_attribute "during"
    ##is_attribute "hours_in_day"
    ##is_attribute "unacknowledged"

  end

  class AlertGroupBuilder < ObjectBuilder

    def builder_setup(name=anonymous_name)
      @result = AlertGroup.new(name)
      @context.last_alert_group = @result
    end
    
    is_block_attribute "includes"
    is_attribute "acknowledgement_time"
    is_attribute "level"
    
    is_builder "notify", NotificationBuilder
    
    def created_notify(notification)
      @result.notifications ||= []
      @result.notifications << notification
    end

  end

  # New list of persons. 
  # @author Yann Golanski
  class PeopleListBuilder < ObjectBuilder

    # Create a new instance and adds it.
    def builder_setup(label)
      pp label
      @result = PeopleList.new(label)
    end

    is_attribute "list"

  end

  # New list of sources.
  # @author Yann Golanski
  class AddSourceListBuilder < ObjectBuilder

    # Create the temporary object.
    def builder_setup(label)
      @result = AddSoruceList.new(label)
    end

    # List of IP addresses or hostnames.
    is_attribute "list"

  end


  # this should live in AlertGroupBuilder but can't due to
  # http://briancarper.net/blog/ruby-instance_eval_constant_scoping_broken
  #
  module ConfigConstants
    URGENT = :urgent
    NORMAL = :normal
    LOW    = :low
  end

  class ConfigurationBuilder < ObjectBuilder

    include ConfigConstants

    is_builder "server", ServerBuilder
    is_builder "notification_method", NotificationMethodBuilder
    is_builder "person", PersonBuilder
    is_builder "alert_group", AlertGroupBuilder
    is_builder "people_list", PeopleListBuilder
    is_builder "add_source_list", AddSourceListBuilder
    is_builder "logger", LoggerBuilder
    
    def initialize
      @context = @result = Configuration.new
      # FIXME: need to test blocks that are not immediately evaluated
    end
    
    def created_server(server)
      raise ArgumentError.new("Only one 'server' clause can be specified") if 
        @result.server
      @result.server = server
    end

    def created_notification_method(notification_method)
      name = notification_method.name
      raise BuildException.new("Duplicate notification '#{name}'") if
        @result.notification_methods[name]
      @result.notification_methods[name] = notification_method
    end

    def created_person(person)
      name = person.username
      raise BuildException.new("Duplicate person '#{name}'") if
        @result.people[name]
      @result.people[person.username] = person
    end

    def created_alert_group(alert_group)
      name = alert_group.name
      raise BuildException.new("Duplicate alert_group '#{name}'") unless
        @result.alert_groups.select { |g| g.name == name }.empty?
      @result.alert_groups << alert_group
    end

    # Create a new instance of people_list.
    #
    # @param [PeopleList] people_list The new list of persons.
    # @return [NULL] nada.
    def created_people_list(people_list)
      label = people_list.label
      raise BuildException.new("Duplicate people_list '#{label}'") if @result.people_lists[label]
      @result.people_lists[label] = people_list
    end

    # Create a new list of sources.
    #
    # @param [] add_source_list 
    # @return [NULL] nada.
    def created_add_source_list(add_source_list)
      @result.source_lists.create_new_list(add_source_list.label,
                                    add_source_list.list)
    end

  end

end
