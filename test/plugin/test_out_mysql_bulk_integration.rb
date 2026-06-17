# coding: utf-8
require 'helper'
require 'mysql2-cs-bind'
require 'fluent/test/driver/output'
require 'fluent/test/helpers'
require 'fluent/plugin/buffer'
require 'fluent/config'
require 'time'

# Integration tests that exercise the real INSERT path against a live MySQL
# server (MySQL 8.4 is used on CI). When no MySQL server is reachable the whole
# test case is omitted, so it is safe to run locally without a database.
class MysqlBulkOutputIntegrationTest < Test::Unit::TestCase
  include Fluent::Test::Helpers

  HOST     = ENV['MYSQL_HOST'] || '127.0.0.1'
  PORT     = (ENV['MYSQL_PORT'] || 3306).to_i
  USERNAME = ENV['MYSQL_USER'] || 'root'
  PASSWORD = ENV['MYSQL_PASSWORD'] || 'hogehoge'
  DATABASE = ENV['MYSQL_DATABASE'] || 'test_app_development'
  TABLE    = 'users'

  def maybe_client(database: nil)
    Mysql2::Client.new(host: HOST, port: PORT, username: USERNAME,
                       password: PASSWORD, database: database)
  rescue => e
    @connection_error = e
    nil
  end

  def setup
    client = maybe_client
    omit "MySQL is not available (#{@connection_error}); skipping integration tests" if client.nil?

    Fluent::Test.setup

    client.query("CREATE DATABASE IF NOT EXISTS `#{DATABASE}`")
    client.close

    @client = maybe_client(database: DATABASE)
    @client.query("DROP TABLE IF EXISTS `#{TABLE}`")
    @client.query(<<-SQL)
      CREATE TABLE `#{TABLE}` (
        `id` INT NOT NULL,
        `user_name` VARCHAR(50) DEFAULT NULL,
        `created_at` DATETIME DEFAULT NULL,
        `login_count` INT DEFAULT NULL,
        PRIMARY KEY (`id`)
      )
    SQL
  end

  def teardown
    return unless @client
    @client.query("DROP TABLE IF EXISTS `#{TABLE}`")
    @client.close
  end

  def create_driver(conf)
    Fluent::Test::Driver::Output.new(Fluent::Plugin::MysqlBulkOutput).configure(conf)
  end

  def base_config(extra = '')
    %[
      host #{HOST}
      port #{PORT}
      database #{DATABASE}
      username #{USERNAME}
      password #{PASSWORD}
      table #{TABLE}
      #{extra}
    ]
  end

  def select_all
    @client.query("SELECT * FROM `#{TABLE}` ORDER BY id").to_a
  end

  # Builds a minimal buffer-chunk-like object so a single write/1 call can be
  # exercised directly. Driving the error path through d.run is unreliable here
  # because flush happens on a background thread that swallows the exception, so
  # we call write/1 ourselves to observe how it handles a failing INSERT.
  # extract_placeholders accepts a Metadata as its chunk argument (the "old
  # plugin" path) and our database/table have no placeholders, so a Metadata
  # extended with #msgpack_each is enough to drive write/1.
  def build_chunk(records, tag: 'test', time: event_time("2016-09-26 12:00:00 UTC"))
    rows = records.map { |record| [tag, time, record] }
    chunk = Fluent::Plugin::Buffer::Metadata.new(nil, nil, nil)
    chunk.define_singleton_method(:msgpack_each) do |&block|
      rows.each { |row| block.call(*row) }
    end
    chunk
  end

  def test_bulk_insert
    conf = base_config(%[
      column_names id,user_name,created_at
      key_names id,user_name,created_at
    ])
    d = create_driver(conf)
    time = event_time("2016-09-26 12:00:00 UTC")
    d.run(default_tag: 'test', flush: true) do
      d.feed(time, { "id" => 1, "user_name" => "alice", "created_at" => "2016-09-26 12:00:00" })
      d.feed(time, { "id" => 2, "user_name" => "bob",   "created_at" => "2016-09-26 12:00:00" })
    end

    rows = select_all
    assert_equal(2, rows.size)
    assert_equal([1, "alice"], [rows[0]["id"], rows[0]["user_name"]])
    assert_equal([2, "bob"],   [rows[1]["id"], rows[1]["user_name"]])
  end

  def test_varchar_is_truncated_to_column_length
    conf = base_config(%[
      column_names id,user_name
      key_names id,user_name
    ])
    d = create_driver(conf)
    long_name = "a" * 100 # column is VARCHAR(50)
    time = event_time("2016-09-26 12:00:00 UTC")
    d.run(default_tag: 'test', flush: true) do
      d.feed(time, { "id" => 1, "user_name" => long_name })
    end

    rows = select_all
    assert_equal(1, rows.size)
    assert_equal(50, rows[0]["user_name"].length)
  end

  # Regression test for the swallow-the-error approach proposed in
  # https://github.com/tagomoris/fluent-plugin-mysql/pull/65 : a failing INSERT
  # (here a NOT NULL violation, the exact error reported in that PR) must raise
  # out of write/1 so Fluentd retries the chunk. If the error were rescued and
  # swallowed, Fluentd would treat the flush as successful and silently drop
  # every record in the chunk.
  def test_failed_insert_raises_so_chunk_is_not_silently_dropped
    conf = base_config(%[
      column_names id,user_name
      key_names id,user_name
    ])
    d = create_driver(conf)
    chunk = build_chunk([{ "id" => nil, "user_name" => "alice" }]) # id is NOT NULL

    assert_raise(Mysql2::Error) do
      d.instance.write(chunk)
    end

    assert_equal(0, select_all.size)
  end

  # A successful flush keeps its MySQL connection open so the next flush reuses
  # it instead of reconnecting every time.
  def test_connection_is_reused_across_successful_writes
    conf = base_config(%[
      column_names id,user_name
      key_names id,user_name
    ])
    d = create_driver(conf)
    begin
      d.instance.write(build_chunk([{ "id" => 1, "user_name" => "alice" }]))
      first = d.instance.handler
      d.instance.write(build_chunk([{ "id" => 2, "user_name" => "bob" }]))

      assert_same(first, d.instance.handler)
      assert_equal(2, select_all.size)
    ensure
      d.instance.close
    end
  end

  def test_on_duplicate_key_update_with_custom_value
    @client.query("INSERT INTO `#{TABLE}` (id, user_name, login_count) VALUES (1, 'alice', 10)")

    conf = base_config(%[
      column_names id,user_name,login_count
      key_names id,user_name,login_count
      on_duplicate_key_update true
      on_duplicate_update_keys login_count
      on_duplicate_update_custom_values ${`login_count` + 1}
    ])
    d = create_driver(conf)
    time = event_time("2016-09-26 12:00:00 UTC")
    d.run(default_tag: 'test', flush: true) do
      d.feed(time, { "id" => 1, "user_name" => "alice", "login_count" => 10 })
    end

    rows = select_all
    assert_equal(1, rows.size)
    assert_equal(11, rows[0]["login_count"])
  end
end
