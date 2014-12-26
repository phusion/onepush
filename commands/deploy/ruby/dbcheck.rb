#!/usr/bin/env ruby
# This script is run by the Ruby Capistrano deploy script to check
# whether the database is empty. It will only be run if the app
# uses Rails.

require 'active_record'

rails_env = ENV['RAILS_ENV'] || ENV['RACK_ENV'] || 'development'
config = YAML.load_file("config/database.yml")[rails_env] || {}
ActiveRecord::Base.establish_connection(config)
case ActiveRecord::Base.connection.adapter_name
when "PostgreSQL"
  sql = %q{
    SELECT n.nspname as "Schema",
    c.relname as "Name",
    CASE c.relkind WHEN 'r' THEN 'table' WHEN 'v' THEN 'view' WHEN 'i' THEN 'index' WHEN 'S' THEN 'sequence' WHEN 's' THEN 'special' END as "Type",
    pg_catalog.pg_get_userbyid(c.relowner) as "Owner"
    FROM pg_catalog.pg_class c
      LEFT JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relkind IN ('r','')
        AND n.nspname <> 'pg_catalog'
        AND n.nspname <> 'information_schema'
        AND n.nspname !~ '^pg_toast'
    AND pg_catalog.pg_table_is_visible(c.oid)
    ORDER BY 1,2;
  }
  if ActiveRecord::Base.connection.select_rows(sql).empty?
    puts "database is empty"
  end
end
