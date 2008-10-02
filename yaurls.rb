#!/usr/bin/ruby
# 
#  Camping application to shortify URLs.
# 
#  Copyright 2008 Jiayong Ou. All rights reserved.

require 'camping'

Camping.goes :YAURLS
# 
# module YAURLS::Models
# 	class	ShortUrl < Base
# 		
# 	end
# end

module YAURLS::Controllers
	class Index < R '/'
		def get
			render :index
		end
	end

	class Create < R '/api/create'
		def get
			@link_id = 'abcd'
			render :result
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
		def get(link_id)
			link_id
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
		url = "http:" + URL(Resolve, @link_id).to_s
		p {"Your short URL: #{a url, :href => url}"}
	end
end