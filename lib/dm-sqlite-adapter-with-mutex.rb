#
# Add a mutex so that we can avoid the 'database is locked' Sqlite3Error
# exception.
#
require 'dm-sqlite-adapter'
require 'monitor'

ADAPTER = DataMapper::Adapters::SqliteAdapter

# better way to alias a private method? (other than "don't"? :) )
ADAPTER.__send__(:alias_method, :initialize_old, :initialize)
ADAPTER.__send__(:undef_method, :initialize)
ADAPTER.__send__(:alias_method, :with_connection_old, :with_connection)
ADAPTER.__send__(:undef_method, :with_connection)

class ADAPTER

  def initialize(*a)
    extend(MonitorMixin)
    initialize_old(*a)
  end

  private

  def with_connection(&block)
    synchronize { with_connection_old(&block) }
  end
end
