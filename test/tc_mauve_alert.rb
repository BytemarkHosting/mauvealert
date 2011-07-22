$:.unshift "../lib"

require 'test/unit'
require 'mauve/alert'
require 'mauve/configuration'
require 'mauve/configuration_builder'
require 'th_mauve_resolv'
require 'pp' 

class TcMauveAlert < Test::Unit::TestCase 

  def test_source_list

    config=<<EOF
source_list "test", %w(test-1.example.com)

source_list "has_ipv4", "0.0.0.0/0"

source_list "has_ipv6", "2000::/3"
EOF

    Mauve::Configuration.current = Mauve::ConfigurationBuilder.parse(config)

    a = Mauve::Alert.new
    a.subject = "www.example.com"

    assert( a.in_source_list?("test")     )
    assert_equal( %w(test has_ipv4).sort, a.source_lists.sort )

    a.subject = "www2.example.com"
    assert( a.in_source_list?("has_ipv6") )
    assert_equal( %w(has_ipv6 has_ipv4).sort, a.source_lists.sort )
  end


  def test_summary

    a = Mauve::Alert.new
    a.summary = "Free swap memory (MB) (memory_swap) is too low"

    assert_match(/memory_swap/, a.summary)

  end


end

