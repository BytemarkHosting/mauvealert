#
# Add a mutex so that we can avoid the 'database is locked' Sqlite3Error
# exception.
#
require 'dm-sqlite-adapter'
require 'monitor'

class DataMapper::Adapters::SqliteAdapter

  include MonitorMixin

  alias_method :with_connection_old, :with_connection

  private

  def with_connection(&block)
    synchronize { with_connection_old(&block) }
  end
end
