$:.unshift "../lib"

require 'th_mauve'
require 'mauve/history'
require 'mauve/server'

class TcMauveHistory < Mauve::UnitTest 

  include Mauve

  def setup
    super
    setup_database
  end

  def teardown
    teardown_database
    super
  end

  def test_save
    Server.instance.setup
    #
    # Make sure events save without nasty html
    #
    h = History.new(:alerts => [], :type => "note", :event => "Hello <script>alert(\"arse\");</script>")

    assert(h.save)
    h.reload
    assert_equal("Hello ",h.event, "HTML not stripped correctly on save.")

    h = History.new(:alerts => [], :type => nil, :event => "Hello")
    assert_raise(DataMapper::SaveFailureError, "History saved with blank type -- validation not working"){h.save}
    assert_equal([:type], h.errors.keys, "Just the type field should be invalid")

  end
end




