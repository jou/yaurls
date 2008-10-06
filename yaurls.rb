#!/usr/bin/ruby
# 
#  Camping application to shortify URLs.
# 
#  Copyright 2008 Jiayong Ou. All rights reserved.

$: << File.join(File.expand_path(File.dirname(__FILE__)), 'lib')

require 'camping'
require 'camping/db'
require 'digest/md5'
require 'uri'
require 'dnsbl'

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
	
  class AddSequence < V 1.1
    def self.up
      create_table :yaurls_sequences
    end 
    
    def self.down
      drop_table :yaurls_sequences
    end
  end
  
  class UrlInvalidException < RuntimeError
    
  end
  
  # Model class for a short URL
  class ShortUrl < Base
    def long_url=(url)
      write_attribute(:long_url, url)
      write_attribute(:url_hash, Digest::MD5.hexdigest(url))
    end
    
    # Parse URL and raise errors when the URL scheme is not allowed or if the URL is not absolute
    def self.parse_url(url)
      uri = URI.parse(url)
      uri.host.downcase!
      
      raise(UrlInvalidException, "URL scheme #{uri.scheme} not allowed.") if !['http', 'https', 'ftp'].include?(uri.scheme)
      raise(UrlInvalidException, "Absolute URL required") if !uri.host
      raise(UrlInvalidException, "URL #{uri} is listed as spam in SURBL or URIBL") if self.is_spam?(uri)
      
      uri.path = '/' if uri.path.empty?
      
      uri
    end
    
    # Checks if url is spam
    def self.is_spam?(uri)
      labels = uri.host.split('.')
      
      return DNSBL.check_domain(uri.host) if labels.length <= 2
      
      for i in (2..labels.length)
        return true if DNSBL.check_domain(labels[-i, i].join('.'))
      end
      
      false
    end
  end
  
  # Sequence to generate shorturl code
  class Sequence < Base
    @@encode_table = [
      "L", "-", "V", "C", "0", "6", "5", "W", "Z", "U", "v", "X", "S", "A", "z", "Q", "O", 
      "8", "l", "4", "T", "F", "Y", "B", "P", "R", "o", "J", "1", "i", "s", "r", "h", "n", 
      "u", "q", "a", "$", "m", "H", "y", "I", "_", "2", "9", "k", "j", "t", "w", "K", "7", 
      "x", "d", "G", "e", "=", "g", "E", "p", "M", "f", "b", "N", "3", "D", "c"
    ]
  
    def self.encode_number(n)
      return @@encode_table[0] if n == 0
    
      result = ''
      base = @@encode_table.length
    
      while n > 0
        remainder = n % base
        n = n / base
        result = @@encode_table[remainder] + result
      end
      result
    end

    def self.next
      seq = self.create
      code = self.encode_number(seq.id)
      
      while ShortUrl.exists?(:code => code)
        seq = self.create
        code = self.encode_number(seq.id)
      end
      
      code
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
      plaintext =  @input.key?('plaintext')
      @headers['Content-Type'] = 'text/plain' if plaintext
      
      url = @input['url']
      code = @input['code']
      ip = @env['REMOTE_ADDR']
      
      if !url
        @headers['Content-Type'] = 'text/plain'
        @status = '403'
        return "No url given!"
      end
      
      begin
        uri = ShortUrl.parse_url(url)
      rescue UrlInvalidException, URI::InvalidURIError => e
        @status = '403'
        @headers['Content-Type'] = 'text/plain'
        return e.to_s
      end
      
      short_url = ShortUrl.find(:first, :conditions => ['url_hash = ?', Digest::MD5.hexdigest(uri.to_s)])
      
      if !short_url
        short_url = ShortUrl.create do |u|
          u.long_url = uri.to_s
          u.code = code ? code : Sequence.next
          u.creator_ip = ip
        end
      end
      
      "http:" + URL(Resolve, short_url.code, '').to_s
    end
  end
  
  class ReverseLookup < R '/api/reverselookup/([^/]+)(.*)'
    def get(code, more_of_query_string)
      @headers['Content-Type'] = 'text/plain'
      
      url = ShortUrl.find(:first, :conditions => ['code = ?', code])
      if url
        result = url.long_url + more_of_query_string
        result += '?'+@env['QUERY_STRING'] if @env['QUERY_STRING'] && !@env['QUERY_STRING'].empty?
        
        result
      else
        @status = '404';
        "Code not found"
      end
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

  class Resolve < R '/([^/]+)(.*)'
    def get(code, more_of_query_string)
      url = ShortUrl.find(:first, :conditions => ['code = ?', code])
      if url
        result = url.long_url + more_of_query_string
        result += '?'+@env['QUERY_STRING'] if @env['QUERY_STRING'] && !@env['QUERY_STRING'].empty?
        
        @headers['Location'] = result
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