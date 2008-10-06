#!/usr/bin/ruby
require 'rubygems'
require 'rack'
require 'yaurls'

# Uncomment and edit your database settings
#Camping::Models::Base.establish_connection :adapter => 'mysql', 
#  :database => 'camping_yourapp', 
#  :username => 'camper', 
#  :password => 'secret'

YAURLS.create
run Rack::Adapter::Camping.new(YAURLS)
