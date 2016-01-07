# -*- encoding : utf-8 -*-
module Fluent
  class Fluent::MysqlBulkOutput < Fluent::BufferedOutput
    Fluent::Plugin.register_output('mysql_bulk', self)

    config_param :host, :string, default: '127.0.0.1'
    config_param :port, :integer, default: 3306
    config_param :database, :string
    config_param :username, :string
    config_param :password, :string, default: '', secret: true

    config_param :column_names, :string
    config_param :key_names, :string, default: nil
    config_param :table, :string

    config_param :on_duplicate_key_update, :bool, default: false
    config_param :on_duplicate_update_keys, :string, default: nil

    attr_accessor :handler

    def initialize
      super
      require 'mysql2-cs-bind'
    end

    def configure(conf)
      super

      if @column_names.nil?
        fail Fluent::ConfigError, 'column_names MUST specified, but missing'
      end

      if @on_duplicate_key_update
        if @on_duplicate_update_keys.nil?
          fail Fluent::ConfigError, 'on_duplicate_key_update = true , on_duplicate_update_keys nil!'
        end
        @on_duplicate_update_keys = @on_duplicate_update_keys.split(',')

        @on_duplicate_key_update_sql = ' ON DUPLICATE KEY UPDATE '
        updates = []
        @on_duplicate_update_keys.each do |update_column|
          updates << "#{update_column} = VALUES(#{update_column})"
        end
        @on_duplicate_key_update_sql += updates.join(',')
      end

      @column_names = @column_names.split(',')
      @key_names = @key_names.nil? ? @column_names : @key_names.split(',')
    end

    def start
      super
      result = client.xquery("SHOW COLUMNS FROM #{@table}")
      @max_lengths = []
      @column_names.each do |column|
        info = result.select { |x| x['Field'] == column }.first
        r = /(char|varchar)\(([\d]+)\)/
        begin
          max_length = info['Type'].scan(r)[0][1].to_i
        rescue
          max_length = nil
        end
        @max_lengths << max_length
      end
    end

    def shutdown
      super
    end

    def format(tag, time, record)
      [tag, time, format_proc.call(tag, time, record)].to_msgpack
    end

    def client
      Mysql2::Client.new(
          host: @host,
          port: @port,
          username: @username,
          password: @password,
          database: @database,
          flags: Mysql2::Client::MULTI_STATEMENTS
        )
    end

    def write(chunk)
      @handler = client
      values = []
      values_template = "(#{ @column_names.map { |key| '?' }.join(',') })"
      chunk.msgpack_each do |tag, time, data|
        values << Mysql2::Client.pseudo_bind(values_template, data)
      end
      sql = "INSERT INTO #{@table} (#{@column_names.join(',')}) VALUES #{values.join(',')}"
      sql += @on_duplicate_key_update_sql if @on_duplicate_key_update

      $log.info "bulk insert values size => #{values.size}"
      @handler.xquery(sql)
      @handler.close
    end

    private

    def format_proc
      proc do |tag, time, record|
        values = []
        @key_names.each_with_index do |key, i|
          if key == '${time}'
            value = Time.at(time).strftime('%Y-%m-%d %H:%M:%S')
          else
            if @max_lengths[i].nil? || record[key].nil?
              value = record[key]
            else
              value = record[key].slice(0, @max_lengths[i])
            end
          end
          values << value
        end
        values
      end
    end
  end
end
