#!/usr/bin/ruby
# 
#  Camping application to shortify URLs.
# 
#  Copyright 2008 Jiayong Ou. All rights reserved.

require 'camping'
require 'camping/db'
require 'digest/md5'

Camping.goes :YAURLS

def YAURLS.create
  YAURLS::Models.create_schema
end

module YAURLS::Models
  # Schema definition
  class CreateUrls < V 1.0
    def self.up
      create_table :yaurls_short_urls do |t|
        t.string :code, :null => false
        t.text :long_url, :null => false
        t.string :url_hash, :null => false
        t.datetime :created_at, :null => false
        t.string :creator_ip, :null => false
      end
      add_index(:yaurls_short_urls, :code, :unique => true)
      add_index(:yaurls_short_urls, :url_hash, :unique => true)
    end
    
    def self.down
      drop_table :yaurls_short_urls
    end
  end
	
  # class AddSequence < V 1.1
  #   def self.up
  #     create_table :sequences do 
  
  # Model class for a short URL
  class ShortUrl < Base
    def long_url=(url)
      write_attribute(:long_url, url)
      write_attribute(:url_hash, Digest::MD5.hexdigest(url))
    end
  end
end

module YAURLS::Controllers
  class Index < R '/'
    def get
      render :index
    end
  end

  class Create < R '/api/create'
    def get
      url = "http://blog.orly.ch/"
      short_url = ShortUrl.create do |u|
        u.long_url = url
        u.code = "b"
        u.creator_ip = "127.0.0.1"
      end
      
      @short_url = short_url
    end
  end
  
  class ReverseLookup < R '/api/reverselookup/(.+)'
    def get(link_id)
      
    end
  end

  class Static < R '/static/(.+)'
    MIME_TYPES = {'.css' => 'text/css', '.js' => 'text/javascript', 
                  '.jpg' => 'image/jpeg', '.png' => 'image/png'}
    PATH = File.expand_path(File.dirname(__FILE__))

    def get(path)
      unless path.include? ".." # prevent directory traversal attacks
        @headers['Content-Type'] = MIME_TYPES[path[/\.\w+$/, 0]] || "text/plain"
        @headers['X-Sendfile'] = "#{PATH}/static/#{path}"
      else
        @headers['Content-Type'] = 'text/plain'
        @status = "403"
        "403 - Invalid path"
      end
    end
  end

  class Resolve < R '/(.+)'
    def get(code)
      url = ShortUrl.find(:first, :conditions => ['code = ?', code])
      if url
        @headers['Location'] = url.long_url
        @status = '301'
      else
        @status = '404'
        "Code not found"
      end
    end
  end
end

module YAURLS::Views
  def layout
    html do
      head do
        title 'srs.li'
        link :rel => 'stylesheet', :type => 'text/css', :href => '/static/yaurls.css'
        script :src => 'http://ajax.googleapis.com/ajax/libs/prototype/1.6.0.2/prototype.js', :type => 'text/javascript'
        script :src => '/static/yaurls.js', :type => 'text/javascript'
      end
      body do
        div.header do
          h1 'srs.li'
          h2 'YA SRSLY! IT SHORTENS URLS!'
        end
        div.content do
          self << yield
        end
        div.footer do
          p do
            "Powered by #{a 'Camping', :href => 'http://code.whytheluckystiff.net/camping/'}
            and pure caffeine"
          end
        end
      end
    end
  end
  
  def index
    form.urlentry :method => 'get', :action => R(Create) do
      div.longurl do
        label "Long URL", :for => 'url'
        input.url! :type => 'text', :name => 'url'
      end
      div.alias do
        label "Alias (optional)", :for => 'alias'
        input.alias! :type => 'text', :name => 'alias'
      end
      input.create_buton :type => 'submit', :value => 'GO GO GADGET!'
    end
    p do
      "Bookmarklet: #{a "SRSLI!", :href => "javascript:window.location='http:#{URL(Create)}?url='+encodeURIComponent(window.location)"}"
    end
  end
  
  def error
    
  end
  
  def result
    link_id = @short_url.code
    url = "http:" + URL(Resolve, link_id).to_s
    p {"Your short URL: #{a url, :href => url}"}
  end
end