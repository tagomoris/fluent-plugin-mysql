
# fluent-plugin-mysql, a plugin for [Fluentd](http://fluentd.org) [![Build Status](https://secure.travis-ci.org/tagomoris/fluent-plugin-mysql.png?branch=master)](http://travis-ci.org/tagomoris/fluent-plugin-mysql)

fluent plugin mysql bulk insert is high performance and on duplicate key update respond.

## Note
fluent-plugin-mysql-bulk merged this repository.

[mysql plugin](README_mysql.md) is deprecated. You should use mysql_bulk.

v0.1.5 only supports fluentd-0.12.X and v0.2.0 only supports fluentd-0.14.X.

## Parameters

param|value
--------|------
host|database host(default: 127.0.0.1)
port|database port(default: 3306)
database|database name(require)
username|user(require)
password|password(default: blank)
sslkey|path to client key(default: nil)
sslcert|path to client cert(default: nil)
sslca|path to ca cert(default: nil)
sslcapath|path to ca certs(default: nil)
sslcipher|ssl cipher(default: nil)
sslverify|verify server certificate(default: nil)
column_names|bulk insert column (require)
key_names|value key names, ${time} is placeholder Time.at(time).strftime("%Y-%m-%d %H:%M:%S") (default : column_names)
json_key_names|Key names which store data as json, comma separator.
unixtimestamp_key_names|Key names which store data as datetime from unix time stamp
table|bulk insert table (require)
on_duplicate_key_update|on duplicate key update enable (true:false)
on_duplicate_update_keys|on duplicate key update column, comma separator
transaction_isolation_level|set transaction isolation level(default: nil)

## Configuration Example(bulk insert)

```
<match mysql.input>
  @type mysql_bulk
  host localhost
  database test_app_development
  username root
  password hogehoge
  column_names id,user_name,created_at,updated_at
  table users
  flush_interval 10s
</match>
```

Assume following input is coming:

```js
mysql.input: {"user_name":"toyama","created_at":"2014/01/03 21:35:15","updated_at":"2014/01/03 21:35:15","dummy":"hogehoge"}
mysql.input: {"user_name":"toyama2","created_at":"2014/01/03 21:35:21","updated_at":"2014/01/03 21:35:21","dummy":"hogehoge"}
mysql.input: {"user_name":"toyama3","created_at":"2014/01/03 21:35:27","updated_at":"2014/01/03 21:35:27","dummy":"hogehoge"}
```

then result becomes as below (indented):

```sql
+-----+-----------+---------------------+---------------------+
| id  | user_name | created_at          | updated_at          |
+-----+-----------+---------------------+---------------------+
| 1   | toyama    | 2014-01-03 21:35:15 | 2014-01-03 21:35:15 |
| 2   | toyama2   | 2014-01-03 21:35:21 | 2014-01-03 21:35:21 |
| 3   | toyama3   | 2014-01-03 21:35:27 | 2014-01-03 21:35:27 |
+-----+-----------+---------------------+---------------------+
```

running query

```sql
INSERT INTO users (id,user_name,created_at,updated_at) VALUES (NULL,'toyama','2014/01/03 21:35:15','2014/01/03 21:35:15'),(NULL,'toyama2','2014/01/03 21:35:21','2014/01/03 21:35:21')
```

## Configuration Example(bulk insert , if duplicate error record update)

```
<match mysql.input>
  @type mysql_bulk
  host localhost
  database test_app_development
  username root
  password hogehoge
  column_names id,user_name,created_at,updated_at
  table users
  on_duplicate_key_update true
  on_duplicate_update_keys user_name,updated_at
  flush_interval 60s
</match>
```

Assume following input is coming:

```js
mysql.input: {"id":"1" ,"user_name":"toyama7","created_at":"2014/01/03 21:58:03","updated_at":"2014/01/03 21:58:03"}
mysql.input: {"id":"2" ,"user_name":"toyama7","created_at":"2014/01/03 21:58:06","updated_at":"2014/01/03 21:58:06"}
mysql.input: {"id":"3" ,"user_name":"toyama7","created_at":"2014/01/03 21:58:08","updated_at":"2014/01/03 21:58:08"}
mysql.input: {"id":"10","user_name":"toyama7","created_at":"2014/01/03 21:58:18","updated_at":"2014/01/03 21:58:18"}
```

then result becomes as below (indented):

```sql
+-----+-----------+---------------------+---------------------+
| id  | user_name | created_at          | updated_at          |
+-----+-----------+---------------------+---------------------+
|   1 | toyama7   | 2014-01-03 21:35:15 | 2014-01-03 21:58:03 |
|   2 | toyama7   | 2014-01-03 21:35:21 | 2014-01-03 21:58:06 |
|   3 | toyama7   | 2014-01-03 21:35:27 | 2014-01-03 21:58:08 |
|  10 | toyama7   | 2014-01-03 21:58:18 | 2014-01-03 21:58:18 |
+-----+-----------+---------------------+---------------------+
```

if duplicate id , update username and updated_at


## Configuration Example(bulk insert,fluentd key different column name)

```
<match mysql.input>
  @type mysql_bulk
  host localhost
  database test_app_development
  username root
  password hogehoge
  column_names id,user_name,created_at,updated_at
  key_names id,user,created_date,updated_date
  table users
  flush_interval 10s
</match>
```

Assume following input is coming:

```js
mysql.input: {"user":"toyama","created_date":"2014/01/03 21:35:15","updated_date":"2014/01/03 21:35:15","dummy":"hogehoge"}
mysql.input: {"user":"toyama2","created_date":"2014/01/03 21:35:21","updated_date":"2014/01/03 21:35:21","dummy":"hogehoge"}
mysql.input: {"user":"toyama3","created_date":"2014/01/03 21:35:27","updated_date":"2014/01/03 21:35:27","dummy":"hogehoge"}
```

then result becomes as below (indented):

```sql
+-----+-----------+---------------------+---------------------+
| id  | user_name | created_at          | updated_at          |
+-----+-----------+---------------------+---------------------+
| 1   | toyama    | 2014-01-03 21:35:15 | 2014-01-03 21:35:15 |
| 2   | toyama2   | 2014-01-03 21:35:21 | 2014-01-03 21:35:21 |
| 3   | toyama3   | 2014-01-03 21:35:27 | 2014-01-03 21:35:27 |
+-----+-----------+---------------------+---------------------+
```

## Configuration Example(bulk insert, time complement)

```
<match mysql.input>
  @type mysql_bulk
  host localhost
  database test_app_development
  username root
  password hogehoge
  column_names id,user_name,created_at
  key_names id,user,${time}
  table users
  flush_interval 10s
</match>
```

Assume following input is coming:

```js
2014-01-03 21:35:15+09:00: mysql.input: {"user":"toyama","dummy":"hogehoge"}
2014-01-03 21:35:21+09:00: mysql.input: {"user":"toyama2","dummy":"hogehoge"}
2014-01-03 21:35:27+09:00: mysql.input: {"user":"toyama3","dummy":"hogehoge"}
```

then `created_at` column is set from time attribute in a fluentd packet:

```sql
+-----+-----------+---------------------+
| id  | user_name | created_at          |
+-----+-----------+---------------------+
| 1   | toyama    | 2014-01-03 21:35:15 |
| 2   | toyama2   | 2014-01-03 21:35:21 |
| 3   | toyama3   | 2014-01-03 21:35:27 |
+-----+-----------+---------------------+
```

## Configuration Example(bulk insert, time complement with specific timezone)

As described above, `${time}` placeholder sets time with `Time.at(time).strftime("%Y-%m-%d %H:%M:%S")`.
This handles the time with fluentd server default timezone.
If you want to use the specific timezone, you can use the include_time_key feature.
This is useful in case fluentd server and mysql have different timezone.
You can use various timezone format. See below.
http://docs.fluentd.org/articles/formatter-plugin-overview

```
<match mysql.input>
  @type mysql_bulk
  host localhost
  database test_app_development
  username root
  password hogehoge

  include_time_key yes
  timezone +00
  time_format %Y-%m-%d %H:%M:%S
  time_key created_at

  column_names id,user_name,created_at
  key_names id,user,created_at
  table users
  flush_interval 10s
</match>
```

Assume following input is coming(fluentd server is using JST +09 timezone):

```js
2014-01-03 21:35:15+09:00: mysql.input: {"user":"toyama","dummy":"hogehoge"}
2014-01-03 21:35:21+09:00: mysql.input: {"user":"toyama2","dummy":"hogehoge"}
2014-01-03 21:35:27+09:00: mysql.input: {"user":"toyama3","dummy":"hogehoge"}
```

then `created_at` column is set from time attribute in a fluentd packet with timezone converted to +00 UTC:

```sql
+-----+-----------+---------------------+
| id  | user_name | created_at          |
+-----+-----------+---------------------+
| 1   | toyama    | 2014-01-03 12:35:15 |
| 2   | toyama2   | 2014-01-03 12:35:21 |
| 3   | toyama3   | 2014-01-03 12:35:27 |
+-----+-----------+---------------------+
```

## Configuration Example(bulk insert with tag placeholder for table name)

This description is for v0.14.X users.

```
<match mysql.input>
  @type mysql_bulk
  host localhost
  database test_app_development
  username root
  password hogehoge
  column_names id,user_name,created_at
  key_names id,user,${time}
  table users_${tag}
  <buffer tag>
    @type memory
    flush_interval 60s
  </buffer>
</match>
```

Assume following input is coming:

```js
2016-09-26 18:42:13+09:00: mysql.input: {"user":"toyama","dummy":"hogehoge"}
2016-09-26 18:42:16+09:00: mysql.input: {"user":"toyama2","dummy":"hogehoge"}
2016-09-26 18:42:19+09:00: mysql.input: {"user":"toyama3","dummy":"hogehoge"}
```

then `created_at` column is set from time attribute in a fluentd packet:

```sql
mysql> select * from users_mysql_input;
+----+-----------+---------------------+
| id | user_name | created_at          |
+----+-----------+---------------------+
|  1 | toyama    | 2016-09-26 18:42:13 |
|  2 | toyama2   | 2016-09-26 18:42:16 |
|  3 | toyama3   | 2016-09-26 18:42:19 |
+----+-----------+---------------------+
3 rows in set (0.00 sec)
```

## Configuration Example(bulk insert with time format placeholder for table name)

This description is for v0.14.X users.

```
<match mysql.input>
  @type mysql_bulk
  host localhost
  database test_app_development
  username root
  password hogehoge
  column_names id,user_name,created_at
  key_names id,user,${time}
  table users_%Y%m%d
  <buffer time>
    @type memory
    timekey 60s
    timekey_wait 60s
  </buffer>
</match>
```

Assume following input is coming:

```js
2016-09-26 18:37:06+09:00: mysql.input: {"user":"toyama","dummy":"hogehoge"}
2016-09-26 18:37:08+09:00: mysql.input: {"user":"toyama2","dummy":"hogehoge"}
2016-09-26 18:37:11+09:00: mysql.input: {"user":"toyama3","dummy":"hogehoge"}
```

then `created_at` column is set from time attribute in a fluentd packet:

```sql
mysql> select * from users_20160926;
+----+-----------+---------------------+
| id | user_name | created_at          |
+----+-----------+---------------------+
|  1 | toyama    | 2016-09-26 18:37:06 |
|  2 | toyama2   | 2016-09-26 18:37:08 |
|  3 | toyama3   | 2016-09-26 18:37:11 |
+----+-----------+---------------------+
3 rows in set (0.00 sec)
```

## spec

```
bundle install
rake test
```

## todo

divide bulk insert(exsample 1000 per)


## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new [Pull Request](../../pull/new/master)

## Copyright

Copyright (c) 2016 Hiroshi Toyama. See [LICENSE](LICENSE.txt) for details.
