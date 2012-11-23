$:.unshift "../lib"

require 'th_mauve'
require 'mauve/datamapper'
require 'mauve/server'
require 'mauve/configuration'
require 'mauve/configuration_builder'
require 'mauve/configuration_builders'
require 'iconv'

class TcMauveDatabasePeculiarities < Mauve::UnitTest
  include Mauve

  def setup
    super
    setup_database
    @temp_db = "mauve_test.#{10.times.collect{ rand(36).to_s(36) }.join}"
  end

  def teardown
    teardown_database
    super
  end

  def test_encoding
    #
    # Don't test unless the DB URL has been set.
    #
    return unless @db_url

    config=<<EOF
server {
  database "#{@db_url}"
}
EOF

    Configuration.current = ConfigurationBuilder.parse(config)
    Server.instance.setup

    x = Hash.new
    x["en"] = "Please rush me my portable walrus polishing kit!"
    x["fi"] = "Ole hyvä kiirehtiä minulle kannettavan mursu kiillotukseen pakki!"
    x["jp"] = "私に私のポータブルセイウチの研磨キットを急いでください！"

    %w(UTF-8 WINDOWS-1252 SHIFT-JIS).each do |enc|
      x.each do |lang, str|
        assert_nothing_raised("Failed to use iconv to convert to #{enc}") { str = Iconv.conv(enc+"//IGNORE", "utf8", str) }
  
        alert = Alert.new(
          :alert_id  => "#{lang}:#{enc}",
          :source    => "test",
          :subject   => str
        )

        assert_nothing_raised("failed to insert #{enc}") { alert.save }
      end
    end
  end
end



class TcMauveDatabasePostgresPeculiarities < TcMauveDatabasePeculiarities
  def setup
    super
    system("createdb #{@temp_db} --encoding UTF8")
    unless $?.success?
      msg = "Skipping postgres tests, as DB creation (#{@temp_db}) failed."
      @temp_db = nil
      flunk(msg)
    end
    # @pg_conn = PGconn.open(:dbname => @temp_db) 
    @db_url = "postgres:///#{@temp_db}"
  end

  def teardown
    # @pg_conn.finish if @pg_conn.is_a?(PGconn) and @pg_conn.status == PGconn::CONNECTION_OK
    super
    (system("dropdb #{@temp_db}") || puts("Failed to drop #{@temp_db}")) if @temp_db
  end
end

class TcMauveDatabaseSqlite3Peculiarities < TcMauveDatabasePeculiarities
  def setup
    super
    # @pg_conn = PGconn.open(:dbname => @temp_db) 
    @db_url = "sqlite3::memory:"
  end

  #
  # This just makes sure our mixin has been added to the SqliteAdapter.
  #
  def test_has_mixin
    assert DataMapper::Adapters::SqliteAdapter.private_instance_methods.include?("with_connection_old")
    assert DataMapper::Adapters::SqliteAdapter.public_instance_methods.include?("synchronize")
  end

end

