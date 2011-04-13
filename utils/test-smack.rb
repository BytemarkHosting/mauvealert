#!/usr/bin/jruby
# CLASSPATH="$CLASSPATH:/home/yann/projects/mauvealert/jars/smack.jar:/home/yann/projects/mauvealert/jars/smackx.jar
# ./test-smack

require 'java'
require '../jars/smack.jar'
require '../jars/smackx.jar'
require 'rubygems'
require 'rainbow'
require 'pp'

include_class "org.jivesoftware.smack.XMPPConnection"
include_class "org.jivesoftware.smackx.muc.MultiUserChat"

user_jid='mauvealert'
password='WojIsEv8ScaufOm1'
msg = "What fresh hell is this? -- Dorothy Parker."
begin

  print "XMPP object instanciated.\n".color(:green)
  xmpp = XMPPConnection.new("chat.bytemark.co.uk")


  print "Connection done.\n".color(:green)
  xmpp.connect
  if true != xmpp.isConnected
    print "Failed to connect".color(:red)
    return -1
  end
  

  print "Login.\n".color(:green)
  xmpp.login(user_jid, password, "Testing_smack")
  if true != xmpp.isAuthenticated() 
    print "Failed to authenticate\n".color(:red)
    return -1
  end
  if true == xmpp.isSecureConnection() 
    print "Connection is secure\n".color(:green)
  else
    print "Connection is NOT secure.\n".color(:yellow)
  end


  print "Get chat manager.\n".color(:green)
  chat = xmpp.getChatManager.createChat(
    "yann@chat.bytemark.co.uk", nil)

  print "Sending message to #{chat.getParticipant}.\n".color(:green)
  chat.sendMessage(msg)


  print "Joining, sending a message and leaving a room.\n".color(:green)
  #muc = MultiUserChat.new(xmpp, "office@conference.chat.bytemark.co.uk")
  muc = MultiUserChat.new(xmpp, "test@conference.chat.bytemark.co.uk")
  muc.join("Mauve alert bot")
  muc.sendMessage(msg)
  sleep 1
  #muc.leave()


  print "Adieu monde cruel!\n".color(:green)
  xmpp.disconnect
  

  print "all done.\n".color(:green)
rescue => ex
  print "EPIC FAIL: Raised #{ex.class} because #{ex.message}\n\n".color(:red)
  raise ex
end

=begin
require 'java'
require './jars/smack.jar' 
require './jars/smackx.jar'
include_class "org.jivesoftware.smack.XMPPConnection"
include_class "org.jivesoftware.smackx.muc.MultiUserChat"
user_jid='mauvealert'
password='WojIsEv8ScaufOm1'
msg = "What fresh hell is this? -- Dorothy Parker."
xmpp = XMPPConnection.new("chat.bytemark.co.uk")
xmpp.connect
xmpp.login(user_jid, password, "mauve_test")

jid="yann@chat.bytemark.co.uk"
chat = xmpp.getChatManager.createChat(jid, nil)
chat.sendMessage(msg)

xmpp.getRoster().reload()
xmpp.getRoster().getPresence(jid).isAvailable()
xmpp.getRoster().getPresence(jid).getStatus()

muc = MultiUserChat.new(xmpp, 'office@conference.chat.bytemark.co.uk/mauvealert')
muc.join("Mauve alert bot")
muc.sendMessage(msg)

muc2 = MultiUserChat.new(xmpp, "test@conference.chat.bytemark.co.uk")  
muc2.join("Mauve alert bot")
muc2.sendMessage(msg)

=end
