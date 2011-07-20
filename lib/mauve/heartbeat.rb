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

    attr_accessor :destination, :summary, :detail
    attr_reader   :sleep_interval, :raise_at 

    def initialize
      super

      @destination    = nil
      @summary        = "Mauve alert server down."
      @detail         = "The Mauve server at #{Server.instance.hostname} has failed to send a heartbeat."
      self.raise_at   = 600
    end

    def raise_at=(i)
      @raise_at = i
      @sleep_interval = ((i.to_f)/2.5).round.to_i
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
      message.raise_time = (MauveTime.now.to_f+self.raise_at).to_i
      message.clear_time = MauveTime.now.to_i

      update.alert << message

      Mauve::Sender.new(self.destination).send(update)
    end

  end

end


