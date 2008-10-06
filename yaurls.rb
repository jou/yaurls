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
      create_table :yaurls_sequences do; end
    end 
    
    def self.down
      drop_table :yaurls_sequences
    end
  end
  
  class UrlInvalidException < RuntimeError; end
  
  # Model class for a short URL
  class ShortUrl < Base
    def long_url=(url)
      write_attribute(:long_url, url)
      write_attribute(:url_hash, Digest::MD5.hexdigest(url))
    end
    
    # Parse URL and raise errors when the URL scheme is not allowed or if the URL is not absolute
    def self.parse_url(url)
      uri = URI.parse(url)
      uri.host.downcase! if uri.host
      
      raise(UrlInvalidException, "Absolute URL required. Did you forget http://?") if !uri.host
      raise(UrlInvalidException, "URL scheme #{uri.scheme} not allowed.") if !['http', 'https', 'ftp'].include?(uri.scheme)
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
    
    # Checks if requesting user is spammer
    def self.is_spammer?(ip)
      return DNSBL.check_ip(ip)
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
      
      # check if encoded value is already given as a code to a shortcut
      # and keep creating until one is free
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
      code = @input['alias']
      has_code = code && !code.empty?
      ip = @env['REMOTE_ADDR']
      
      if blacklist = ShortUrl.is_spammer?(ip)
        @headers['Content-Type'] = 'text/plain'
        @status = '403'
        return "#{ip} is blacklisted on #{blacklist}"
      end
      
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
      
      
      if has_code && ShortUrl.exists?(:code => code)
        @status = '403'
        @headers['Content-Type'] = 'text/plain'
        return "Alias #{code} is already taken"
      end
      
      if !short_url
        short_url = ShortUrl.create do |u|
          u.long_url = uri.to_s
          u.code = has_code ? code : Sequence.next
          u.creator_ip = ip
        end
      end
      
      if plaintext
        "http:" + URL(Resolve, short_url.code, '').to_s
      else
        @short_url = short_url
        render :result
      end
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
  
  class ApiDocs < R '/api/docs'
    def get
      render :api_docs
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
        @headers['Content-Type'] = 'text/plain'
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
      end
      body do
        div.header do
          h1 {a 'srs.li', :href => '/'}
          h2 'YA SRSLY! IT SHORTENS URLS!'
        end
        div.content do
          self << yield
        end
        div.footer do
          p do
            <<-eos
              Powered by #{a 'Camping', :href => 'http://code.whytheluckystiff.net/camping/'}, in need of a clever
              slogan. #{a.orly_link! 'code.orly.ch', :href => 'http://code.orly.ch/'}
            eos
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
    p.more do
      <<-eos
        Bookmarklet: #{a "SRSLI!", :href => "javascript:window.location='http:#{URL(Create)}?url='+encodeURIComponent(window.location)"} #{span.separator "|"}
        API: #{a "Documentation", :href => R(ApiDocs)}
      eos
    end
  end
  
  def error
    
  end
  
  def result
    link_id = @short_url.code
    url = "http:" + URL(Resolve, link_id, '').to_s
    p {"Your short URL: #{a url, :href => url}"}
  end
  
  def api_docs
    h1 "API"
    p "srs.li provides a simple REST interface for your bot-building pleasure"
    h2 "Create"
    p do 
      <<-eos
        Simply make a GET request to #{b "http:#{URL(Create)}?plaintext&url=http://www.example.com/"} and you'll get your
        shortened URL as plain text back. The 'plaintext' parameter just has to be present, it's value is ignored.
      eos
    end
    p do
      <<-eos
        If everything was alright, you get a HTTP 200. If not, well... shit happens. The response body should explain what
        went wrong.
      eos
    end
    h2 "Reverse Lookup"
    p do
      <<-eos
        Another API method is doing reverse lookup, that is giving it the short url and getting the long one back. To do that,
        tell your HTTP client to GET #{b "http:#{URL(ReverseLookup, 'ID', '')}"} (replace ID with the link id, the stuff after
        the slash after the hostname).
      eos
    end
    p do
      <<-eos
        Again, if everything was alright, you get a HTTP 200. If the link id was not found, you'd get a HTTP 404.
      eos
    end
  end
end
