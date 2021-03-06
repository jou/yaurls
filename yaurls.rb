#!/usr/bin/ruby
# 
#  Camping application to shortify URLs.
# 
#  Copyright 2008 Jiayong Ou. All rights reserved.

require 'rubygems'
require 'bundler/setup'
require 'active_support'
require 'camping'
require 'digest/md5'
require 'uri'
require 'dnsbl-client'
require 'net/http'
require 'nokogiri'
require 'singleton'

Camping.goes :YAURLS

module YAURLS::Models
  class UrlInvalidException < RuntimeError; end

  class OtherShortenerList
    include Singleton

    attr_accessor :other_shorteners

    def initialize(list_file = File.dirname(__FILE__)+'/data/url-shorteners.txt')
      @other_shorteners = []
      File.open(list_file, 'r') do |f|
        f.each_line do |line|
          @other_shorteners << line.strip
        end
      end
    end

    def is_shortener?(domain)
      @other_shorteners.index(domain)
    end
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
      uri.host.downcase! if uri.host
      
      raise(UrlInvalidException, "Absolute URL required. Did you forget http://?") if !uri.host
      raise(UrlInvalidException, "URL scheme #{uri.scheme} not allowed.") if !['http', 'https', 'ftp'].include?(uri.scheme)
      raise(UrlInvalidException, "#{uri.host} is an other URL shortener. Please don't do that.") if OtherShortenerList.instance.is_shortener?(uri.host)
      raise(UrlInvalidException, "URL #{uri} is listed as spam in SURBL or URIBL") if self.is_spam?(uri)
      raise(UrlInvalidException, "URL #{uri} has been blacklisted due to abuse") if self.blacklisted?(uri)
      
      uri.path = '/' if uri.path.empty?
      
      uri
    end

    def self.dnsbl
      @dnsbl ||= DNSBL::Client.new
    end
    
    # Checks if url is spam
    def self.is_spam?(uri)
      dnsbl_client = self.dnsbl
      result = dnsbl_client.lookup(uri.host)

      result && result.length > 0
    end

    def self.blacklist
      return @blacklist if @blacklist

      @blacklist = []
      File.open(File.dirname(__FILE__)+'/data/blacklist.txt') do |f|
        f.each_line do |line|
          @blacklist << line.strip
        end
      end

      @blacklist
    end

    def self.blacklisted?(uri)
      self.blacklist.include?(uri.host)
    end
    
    # check if `rel` or `rev` attribute and its value combined
    # could be a short url
    def self.is_short_url_link?(attribute, val)
      attribute = attribute.to_sym
      val = val.to_s.downcase
      case attribute
        when :rel
          return %w(shorturl shorturi shortlink).include?(val)
        when :rev
          return %w(canonical).include?(val)
      end
    end
    
    # try to parse Link: response header for short links
    def self.parse_link_from_header(response)
      link_header = response['link']
      url = nil
      
      if link_header
          matches = link_header.match(/<([^>]+)>; (rel|rev)=(.+)$/)
          if matches
            url = matches[1] if self.is_short_url_link?(matches[2], matches[3])
          end
      end
      
      url
    end
    
    # try to parse <link> elements in the response body to find one with
    # a suitable `rel` or `rev` attribute
    def self.parse_link_from_body(response)
      doc = Nokogiri::HTML(response.body)
      
      link = doc.css('link[rel], link[rev]').find do |link|
        if link[:rev]
          self.is_short_url_link?(:rev, link[:rev])
        elsif link[:rel]
          self.is_short_url_link?(:rel, link[:rel])
        end
      end
      
      return link[:href] if link
    end
    
    # Checks if the target site provides a short URL via rel=shorturl or rev=canonical
    def self.provided_short_url(uri)
      return nil unless %w(http https).include?(uri.scheme)
      
      begin
        short_url = Net::HTTP.start(uri.host, uri.port) do |http|
          head_response = http.head(uri.request_uri)
          head_link = self.parse_link_from_header(head_response)
          return head_link if head_link
        
          get_response = http.get(uri.request_uri)
          get_link = self.parse_link_from_header(get_response)
          return get_link if get_link
        
          if get_response.content_type
          
          end
          body_link = self.parse_link_from_body(get_response)
          return body_link if body_link
        end
      rescue
        nil
      end
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
    
    @@reserved = %w(api static)
    
    # Encode a number with @@encode_table. @@encode_table.length is the base and
    # the elements represent the digits
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

    # Generate next element in the sequence. The sequence are generated by putting rows
    # into a table with only an id, get the inserted id and encode the value. If the
    # encoded value is already taken as a code in a ShortUrl, repeat until it hits
    # a free value
    def self.next
      seq = self.create
      code = self.encode_number(seq.id)
      
      # check if encoded value is already given as a code to a shortcut
      # and keep creating until one is free
      while @@reserved.include?(code) || ShortUrl.exists?(:code => code)
        seq = self.create
        code = self.encode_number(seq.id)
      end
      
      code
    end
  end
  
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
end

module YAURLS::Controllers
  class Index < R '/'
    def get
      render :index
    end
  end

  class Create < R '/api/create'
    def display_url(short_url)
      "http://srs.li/#{short_url.code}"
    end
    
    def get
      plaintext =  @input.key?('plaintext')
      @headers['Content-Type'] = 'text/plain' if plaintext
      
      url = @input['url']
      code = @input['alias']
      has_code = code && !code.empty?

      x_forwarded_for = @env['HTTP_X_FORWARDED_FOR']

      # Requests probably came from a reverse proxy if it's from localhost
      # and X-Forwarded-For header is set
      ip = if x_forwarded_for && @env['REMOTE_ADDR'] == '127.0.0.1' then
             # Varnish appends ', client_id', so the last one should be the one
             # varnish handled
             x_forwarded_for.split(", ").last
           else
             @env['REMOTE_ADDR']
           end
      
      if !url
        @headers['Content-Type'] = 'text/plain'
        @status = '403'
        return "Error: No url given!"
      end
      
      begin
        uri = ShortUrl.parse_url(url)
      rescue UrlInvalidException, URI::InvalidURIError => e
        @status = '403'
        @headers['Content-Type'] = 'text/plain'
        return "Error: #{e.to_s}"
      end
      
      short_url = ShortUrl.find(:first, :conditions => ['url_hash = ?', Digest::MD5.hexdigest(uri.to_s)])
      
      if has_code && ShortUrl.exists?(:code => code)
        @status = '403'
        @headers['Content-Type'] = 'text/plain'
        return "Error: Alias #{code} is already taken"
      end
      
      if short_url
        @short_url = display_url(short_url)
      else
        # no short url created yet? check if site provides one
        provided_url = ShortUrl.provided_short_url(uri)
        
        if provided_url
          @short_url = provided_url
        else
          short_url = ShortUrl.create do |u|
            u.long_url = uri.to_s
            u.code = has_code ? code : Sequence.next
            u.creator_ip = ip
          end
          @short_url = display_url(short_url)
        end
      end
      
      if plaintext
        @short_url
      else
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
        "Error: Code not found"
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
        "Error: 403 - Invalid path"
      end
    end
  end

  class Resolve < R '/([^/]+)(.*)'
    def get(code, more_of_query_string)
      url = ShortUrl.find(:first, :conditions => ['code = ?', code])
      if url
        uri = URI.parse(url.long_url)
        if YAURLS::Models::ShortUrl.is_spam?(uri) || YAURLS::Models::ShortUrl.blacklisted?(uri)
          @status = 403
          @url = url
          return render :spam
        end
        result = url.long_url + more_of_query_string
        result += '?'+@env['QUERY_STRING'] if @env['QUERY_STRING'] && !@env['QUERY_STRING'].empty?
        
        @headers['Location'] = result
        @status = '301'
      else
        @headers['Content-Type'] = 'text/plain'
        @status = '404'
        "Error: Code not found"
      end
    end
    
    def head(code, more_of_query_string)
      url = ShortUrl.find(:first, :conditions => ['code = ?', code])
      if url
        result = url.long_url + more_of_query_string
        result += '?'+@env['QUERY_STRING'] if @env['QUERY_STRING'] && !@env['QUERY_STRING'].empty?
        
        @headers['Location'] = result
        @status = '301'
      else
        @headers['Content-Type'] = 'text/plain'
        @status = '404'
      end
    end
  end
end

module YAURLS::Views
  def layout
    capture do
      xhtml_transitional do
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
      span do
        "Bookmarklet: #{a "SRSLI!", :href => "javascript:window.location='http://srs.li/api/create?url='+encodeURIComponent(window.location)"}"
      end
      span.separator " | "
      span do
        "API: #{a "Documentation", :href => "/api/docs"}"
      end
    end
  end
  
  def error
    
  end
  
  def result
    p {"Your short URL: #{a @short_url, :href => @short_url, :id => :short_url}"}
  end
  
  def api_docs
    h1 "API"
    p "srs.li provides a simple REST interface for your bot-building pleasure"
    h2 "Create"
    p do 
      <<-eos
        Simply make a GET request to #{b "http://srs.li/api/create?plaintext&url=http://www.example.com/"} and you'll get your
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
        tell your HTTP client to GET #{b "http://srs.li/api/reverselookup/ID"} (replace ID with the link id, the stuff after
        the slash after the hostname).
      eos
    end
    p do
      <<-eos
        Again, if everything was alright, you get a HTTP 200. If the link id was not found, you'd get a HTTP 404.
      eos
    end
  end

  def spam
    h1 "Spam"
    p do
      <<-eos
        #{URI.parse(@url.long_url).host} has been marked as spam
      eos
    end
  end
end

def YAURLS.create
  YAURLS::Models.create_schema
end
