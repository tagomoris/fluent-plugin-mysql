# fluent-plugin-mysql

## Component

### MysqlOutput

Plugin to store mysql tables over SQL, to each columns per values, or to single column as json.

## Configuration

### MysqlOutput

MysqlOutput needs MySQL server's host/port/database/username/password, and INSERT format as SQL, or as table name and columns.

    <match output.by.sql.*>
      type mysql
      host master.db.service.local
      # port 3306 # default
      database application_logs
      username myuser
      password mypass
      key_names status,bytes,vhost,path,rhost,agent,referer
      sql INSERT INTO accesslog (status,bytes,vhost,path,rhost,agent,referer) VALUES (?,?,?,?,?,?,?)
      flush_intervals 5s
    </match>
    
    <match output.by.names.*>
      type mysql
      host master.db.service.local
      database application_logs
      username myuser
      password mypass
      key_names status,bytes,vhost,path,rhost,agent,referer
      table accesslog
      # 'columns' names order must be same with 'key_names'
      columns status,bytes,vhost,path,rhost,agent,referer
      tag_column tag   # optional
      time_column time # optional
      flush_intervals 5s
    </match>

Or, insert json into single column.

    <match output.as.json.*>
      type mysql
      host master.db.service.local
      database application_logs
      username root
      table accesslog
      columns jsondata
      tag_column tag   # optional
      time_column time # optional
      format json
      flush_intervals 5s
    </match>

Now, out_mysql cannnot handle tag/time as output data.

## TODO

* implement 'tag_mapped'

## Copyright

Copyright:: Copyright (c) 2012- TAGOMORI Satoshi (tagomoris)
License::   Apache License, Version 2.0
