require 'helper'
require 'mysql2-cs-bind'

class MysqlBulkOutputTest < Test::Unit::TestCase
  def setup
    Fluent::Test.setup
  end

  def create_driver(conf = CONFIG, tag = 'test')
    d = Fluent::Test::BufferedOutputTestDriver.new(Fluent::MysqlBulkOutput, tag).configure(conf)
    d.instance.instance_eval {
      def client
        obj = Object.new
        obj.instance_eval {
          def xquery(*args); [1]; end
          def close; true; end
        }
        obj
      end
    }
    d
  end

  def test_configure_error
    assert_raise(Fluent::ConfigError) do
      d = create_driver %[
        host localhost
        database test_app_development
        username root
        password hogehoge
        table users
        on_duplicate_key_update true
        on_duplicate_update_keys user_name,updated_at
        flush_interval 10s
      ]
    end

    assert_raise(Fluent::ConfigError) do
      d = create_driver %[
        host localhost
        database test_app_development
        username root
        password hogehoge
        column_names id,user_name,created_at,updated_at
        table users
        on_duplicate_key_update true
        flush_interval 10s
      ]
    end

    assert_raise(Fluent::ConfigError) do
      d = create_driver %[
        host localhost
        username root
        password hogehoge
        column_names id,user_name,created_at,updated_at
        table users
        on_duplicate_key_update true
        on_duplicate_update_keys user_name,updated_at
        flush_interval 10s
      ]
    end
  end

  def test_configure
    # not define format(default csv)
    assert_nothing_raised(Fluent::ConfigError) do
      d = create_driver %[
        host localhost
        database test_app_development
        username root
        password hogehoge
        column_names id,user_name,created_at,updated_at
        table users
        on_duplicate_key_update true
        on_duplicate_update_keys user_name,updated_at
        flush_interval 10s
      ]
    end

    assert_nothing_raised(Fluent::ConfigError) do
      d = create_driver %[
        database test_app_development
        username root
        password hogehoge
        column_names id,user_name,created_at,updated_at
        table users
      ]
    end

    assert_nothing_raised(Fluent::ConfigError) do
      d = create_driver %[
        database test_app_development
        username root
        password hogehoge
        column_names id,user_name,created_at,updated_at
        table users
        on_duplicate_key_update true
        on_duplicate_update_keys user_name,updated_at
      ]
    end

    assert_nothing_raised(Fluent::ConfigError) do
      d = create_driver %[
        database test_app_development
        username root
        password hogehoge
        column_names id,user_name,created_at,updated_at
        key_names id,user,created_date,updated_date
        table users
        on_duplicate_key_update true
        on_duplicate_update_keys user_name,updated_at
      ]
    end
  end

  def test_variables
    d = create_driver %[
      database test_app_development
      username root
      password hogehoge
      column_names id,user_name,created_at,updated_at
      table users
      on_duplicate_key_update true
      on_duplicate_update_keys user_name,updated_at
    ]

    assert_equal ['id','user_name','created_at','updated_at'], d.instance.key_names
    assert_equal ['id','user_name','created_at','updated_at'], d.instance.column_names
    assert_equal " ON DUPLICATE KEY UPDATE user_name = VALUES(user_name),updated_at = VALUES(updated_at)", d.instance.instance_variable_get(:@on_duplicate_key_update_sql)

    d = create_driver %[
      database test_app_development
      username root
      password hogehoge
      column_names id,user_name,created_at,updated_at
      table users
    ]

    assert_equal ['id','user_name','created_at','updated_at'], d.instance.key_names
    assert_equal ['id','user_name','created_at','updated_at'], d.instance.column_names
    assert_nil d.instance.instance_variable_get(:@on_duplicate_key_update_sql)

    d = create_driver %[
      database test_app_development
      username root
      password hogehoge
      key_names id,user_name,created_at,updated_at
      column_names id,user,created_date,updated_date
      table users
    ]

    assert_equal ['id','user_name','created_at','updated_at'], d.instance.key_names
    assert_equal ['id','user','created_date','updated_date'], d.instance.column_names
    assert_nil d.instance.instance_variable_get(:@on_duplicate_key_update_sql)
  end
end
