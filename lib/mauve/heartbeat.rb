require 'mauve/sender'
require 'mauve/proto'
require 'mauve/mauve_thread'
require 'log4r'

#
# This class is responsible for sending a heartbeat to another mauve instance elsewhere.
#
module Mauve

  class Heartbeat < MauveThread

    include Singleton

    attr_reader   :raise_after, :destination, :summary, :detail

    def initialize
      super

      @destination    = nil
      @summary        = "Mauve alert server heartbeat failed"
      @detail         = "The Mauve server at #{Server.instance.hostname} has failed to send a heartbeat."
      @raise_after    = 310
      @poll_every     = 60
    end

    def raise_after=(i)
      raise ArgumentError "raise_after must be an integer" unless i.is_a?(Integer)      
      @raise_after = i
    end

    alias send_every=  poll_every=

    def summary=(s)
      raise ArgumentError "summary must be a string" unless s.is_a?(String)
      @summary = s
    end

    def detail=(d)
      raise ArgumentError "detail must be a string" unless d.is_a?(String)
      @detail = d
    end

    def destination=(d)
      raise ArgumentError "destination must be a string" unless d.is_a?(String)
      @destination = d
    end

    def logger
      @logger ||= Log4r::Logger.new(self.class.to_s)
    end

    def main_loop
      #
      # Don't send if no destination set.
      #
      return if @destination.nil?

      update = Mauve::Proto::AlertUpdate.new
      update.replace = false
      update.alert = []
      update.source = Server.instance.hostname
      update.transmission_id = rand(2**63)

      message = Mauve::Proto::Alert.new
      message.id = "mauve-heartbeat"
      message.summary = self.summary
      message.detail = self.detail
      message.raise_time = (Time.now.to_f+self.raise_after).to_i
      message.clear_time = Time.now.to_i

      update.alert << message

      Mauve::Sender.new(self.destination).send(update)
      logger.debug "Sent to #{self.destination}"
    end

  end

end


