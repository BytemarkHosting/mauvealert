$:.unshift "../lib"

require 'test/unit'
require 'mauve/alert_group'
require 'th_mauve_resolv'
require 'pp' 

class TcMauveAlert < Test::Unit::TestCase 

  def test_matches_alert

    alert = Mauve::Alert.new

    alert_group = Mauve::AlertGroup.new("test")

    alert_group.includes = Proc.new { true }
    assert( alert_group.matches_alert?(alert) )

    alert_group.includes = Proc.new { false }
    assert( !alert_group.matches_alert?(alert) )

    alert_group.includes = Proc.new { summary =~ /Free swap/ }
    alert.summary = "Free swap memory (mem_swap) too low"
    assert( alert_group.matches_alert?(alert) )
    alert.summary = "Free memory (mem_swap) too low"
    assert( ! alert_group.matches_alert?(alert) )

    alert_group.includes = Proc.new{ source == 'supportbot' }
    alert.source = "supportbot"
    assert( alert_group.matches_alert?(alert) )
    alert.source = "support!"
    assert( ! alert_group.matches_alert?(alert) )
    
    alert_group.includes = Proc.new{ /raid/i.match(summary) }
    alert.summary = "RAID failure"
    assert( alert_group.matches_alert?(alert) )
    alert.summary = "Disc failure"
    assert( ! alert_group.matches_alert?(alert) )
  end



end




