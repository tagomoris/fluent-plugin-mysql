require 'fluent/plugin/output'

module Fluent::Plugin
  class MysqlBulkOutput < Output
    Fluent::Plugin.register_output('mysql_bulk', self)

    helpers :compat_parameters, :inject

    config_param :host, :string, default: '127.0.0.1',
                 desc: "Database host."
    config_param :port, :integer, default: 3306,
                 desc: "Database port."
    config_param :database, :string,
                 desc: "Database name."
    config_param :username, :string,
                 desc: "Database user."
    config_param :password, :string, default: '', secret: true,
                 desc: "Database password."

    config_param :column_names, :string,
                 desc: "Bulk insert column."
    config_param :key_names, :string, default: nil,
                 desc: <<-DESC
Value key names, ${time} is placeholder Time.at(time).strftime("%Y-%m-%d %H:%M:%S").
DESC
    config_param :json_key_names, :string, default: nil,
                  desc: "Key names which store data as json"
    config_param :table, :string,
                 desc: "Bulk insert table."

    config_param :unixtimestamp_key_names, :string, default: nil,
                 desc: "Key names which store data as datetime from unix time stamp"

    config_param :on_duplicate_key_update, :bool, default: false,
                 desc: "On duplicate key update enable."
    config_param :on_duplicate_update_keys, :string, default: nil,
                 desc: "On duplicate key update column, comma separator."
    config_param :on_duplicate_update_custom_values, :string, default: nil,
                 desc: "On_duplicate_update_custom_values, comma separator. specify the column name is insert value, custom value is use ${sql conditions}"

    attr_accessor :handler

    def initialize
      super
      require 'mysql2-cs-bind'
    end

    def configure(conf)
      compat_parameters_convert(conf, :buffer, :inject)
      super

      if @column_names.nil?
        fail Fluent::ConfigError, 'column_names MUST specified, but missing'
      end

      if @on_duplicate_key_update
        if @on_duplicate_update_keys.nil?
          fail Fluent::ConfigError, 'on_duplicate_key_update = true , on_duplicate_update_keys nil!'
        end
        @on_duplicate_update_keys = @on_duplicate_update_keys.split(',')

        if !@on_duplicate_update_custom_values.nil?
          @on_duplicate_update_custom_values = @on_duplicate_update_custom_values.split(',')
          if @on_duplicate_update_custom_values.length != @on_duplicate_update_keys.length
            fail Fluent::ConfigError, <<-DESC
on_duplicate_update_keys and on_duplicate_update_custom_values must be the same length
DESC
          end
        end

        @on_duplicate_key_update_sql = ' ON DUPLICATE KEY UPDATE '
        updates = []
        @on_duplicate_update_keys.each_with_index do |update_column, i|
          if @on_duplicate_update_custom_values.nil? || @on_duplicate_update_custom_values[i] == "#{update_column}"
            updates << "#{update_column} = VALUES(#{update_column})"
          else
            value = @on_duplicate_update_custom_values[i].to_s.match(/\${(.*)}/)[1]
            escape_value = Mysql2::Client.escape(value)
            updates << "#{update_column} = #{escape_value}"
          end
        end
        @on_duplicate_key_update_sql += updates.join(',')
      end

      @column_names = @column_names.split(',').collect(&:strip)
      @key_names = @key_names.nil? ? @column_names : @key_names.split(',').collect(&:strip)
      @json_key_names = @json_key_names.split(',') if @json_key_names
      @unixtimestamp_key_names = @unixtimestamp_key_names.split(',') if @unixtimestamp_key_names
    end

    def check_table_schema(database: @database, table: @table)
      result = client(database).xquery("SHOW COLUMNS FROM #{table}")
      max_lengths = []
      @column_names.each do |column|
        info = result.select { |x| x['Field'] == column }.first
        r = /(char|varchar)\(([\d]+)\)/
        begin
          max_length = info['Type'].scan(r)[0][1].to_i
        rescue
          max_length = nil
        end
        max_lengths << max_length
      end
      max_lengths
    end

    def format(tag, time, record)
      record = inject_values_to_record(tag, time, record)
      [tag, time, record].to_msgpack
    end

    def formatted_to_msgpack_binary
      true
    end

    def client(database)
      Mysql2::Client.new(
          host: @host,
          port: @port,
          username: @username,
          password: @password,
          database: database,
          flags: Mysql2::Client::MULTI_STATEMENTS
        )
    end

    def expand_placeholders(metadata)
      database = extract_placeholders(@database, metadata).gsub('.', '_')
      table = extract_placeholders(@table, metadata).gsub('.', '_')
      return database, table
    end

    def write(chunk)
      database, table = expand_placeholders(chunk.metadata)
      max_lengths = check_table_schema(database: database, table: table)
      @handler = client(database)
      values = []
      values_template = "(#{ @column_names.map { |key| '?' }.join(',') })"
      chunk.msgpack_each do |tag, time, data|
        data = format_proc.call(tag, time, data, max_lengths)
        values << Mysql2::Client.pseudo_bind(values_template, data)
      end
      sql = "INSERT INTO #{table} (#{@column_names.map{|x| "`#{x.to_s.gsub('`', '``')}`"}.join(',')}) VALUES #{values.join(',')}"
      sql += @on_duplicate_key_update_sql if @on_duplicate_key_update

      log.info "bulk insert values size (table: #{table}) => #{values.size}"
      @handler.xquery(sql)
      @handler.close
    end

    private

    def format_proc
      proc do |tag, time, record, max_lengths|
        values = []
        @key_names.each_with_index do |key, i|
          if key == '${time}'
            value = Time.at(time).strftime('%Y-%m-%d %H:%M:%S')
          else
            if max_lengths[i].nil? || record[key].nil?
              value = record[key]
            else
              value = record[key].to_s.slice(0, max_lengths[i])
            end

            if @json_key_names && @json_key_names.include?(key)
              value = value.to_json
            end

            if @unixtimestamp_key_names && @unixtimestamp_key_names.include?(key)
              value = Time.at(value).strftime('%Y-%m-%d %H:%M:%S')
            end
          end
          values << value
        end
        values
      end
    end
  end
end
