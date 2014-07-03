# encoding: UTF-8
require 'mauve/proto'
require 'mauve/sender'

module Mauve
  #
  # This class can be used in simple cases where all the program needs to do is
  # send an update about a single alert. 
  #
  # In its simplest form, this could be something like
  #
  #   Mauve::QuickUpdate.new("foo").raise! 
  #
  # sends a "raise" to the default mauve destination about alert ID "foo".
  #
  # It can be used to do set more details about the alert. 
  #
  #   update = Mauve::QuickUpdate.new("foo")
  #   update.summary = "Foo backups failed"
  #   update.detail  = cmd_output
  #   update.raise!
  #
  # Another example might be a heartbeat.
  #
  #   update = Mauve::QuickUpdate.new("heartbeat")
  #   update.summary  = "Heartbeat for this.host.name not received"
  #   update.detail   = "Maybe this host is down, or if not, cron has stopped running."
  #   update.raise_at = Time.now + 600
  #   update.clear_at = now
  #   update.suppress_until = Time.now + 900
  #   update.send
  #
  class QuickUpdate

   def initialize(alert_id)
      raise ArgumentError, "alert_id must be a String, or respond to to_s" unless alert_id.is_a?(String) or alert_id.respond_to?("to_s")

      @verbose = false

      @update = Mauve::Proto::AlertUpdate.new
      @update.replace = false
      @update.alert = []

      @alert = Mauve::Proto::Alert.new
      @alert.id = alert_id.to_s

      @update << @alert
    end

    #
    # Sets the replace flag for the whole update.  Defaults to false.
    #
    def replace=(bool)
      raise ArgumentError, "replace must either be true or false" unless bool.is_a?(TrueClass) or bool.is_a?(FalseClass)

      @update.replace = bool
    end

    #
    # Sets the verbose flag for the update process.  Defaults to false.
    #
    def verbose=(bool)
      raise ArgumentError, "verbose must either be true or false" unless bool.is_a?(TrueClass) or bool.is_a?(FalseClass)

      @verbose = bool
    end

    #
    # Sets the source of the alert.  Defaults to the machine's hostname.
    #
    def source=(s)
      raise ArgumentError, "source must be a String, or respond to to_s" unless s.is_a?(String) or s.respond_to?("to_s")

      @update.source = s.to_s
    end

    #
    # Sets the alert summary.  Must be a string or something that can convert to a string.
    #
    def summary=(s)
      raise ArgumentError, "summary must be a String, or respond to to_s" unless s.is_a?(String) or s.respond_to?("to_s")

      @alert.summary = s.to_s
    end

    #
    # Sets the alert detail.  Must be a string or something that can convert to a string.
    #
    def detail=(s)
      raise ArgumentError, "detail must be a String, or respond to to_s" unless s.is_a?(String) or s.respond_to?("to_s")

      @alert.detail = s
    end

    #
    # Sets the alert summary. Must be a string or something that can convert to a string.
    #
    def subject=(s)
      raise ArgumentError, "subject must be a String, or respond to to_s" unless s.is_a?(String) or s.respond_to?("to_s")

      @alert.subject = s
    end

    #
    # Sets the raise time.  Must be an Integer (epoch time) or a Time.
    #
    def raise_time=(t)
      raise ArgumentError, "raise_time must be a Time or an Integer" unless t.is_a?(Time) or t.is_a?(Integer)
      t = t.to_i if t.is_a?(Time)

      @alert.raise_time = t
    end

    alias raise_at= raise_time=

    #
    # Sets the clear time.  Must be an Integer (epoch time) or a Time.
    #
    def clear_time=(t)
      clear ArgumentError, "clear_time must be a Time or an Integer" unless t.is_a?(Time) or t.is_a?(Integer)
      t = t.to_i if t.is_a?(Time)

      @alert.clear_time = t
    end

    alias clear_at= clear_time=

    #
    # Sets the time after which alerts will get sent.  Must be an Integer (epoch time) or a Time.
    #
    def suppress_until=(t)
      clear ArgumentError, "suppress_until must be a Time or an Integer" unless t.is_a?(Time) or t.is_a?(Integer)
      t = t.to_i if t.is_a?(Time)

      @alert.suppress_until = t
    end

    #
    # Immediately send a raise message.  The raise_time defaults to Time#now.
    #
    def raise!(t = Time.now)
      self.raise_time = t
      self.send
    end

    #
    # Immediately send a clear message.  The clear_time defaults to Time#now.
    #
    def clear!(t = Time.now)
      self.clear_time = t
      self.send
    end

    #
    # This sends the alert.  If destinations are left as nil, then the default
    # as per Mauve::Sender are used.
    #
    def send(destinations = nil)
      Mauve::Sender.new(destinations).send(@update, @verbose)
    end

  end

end


