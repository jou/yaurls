# Wut?

Yet Another URL Shortifyer powers [srs.li](http://srs.li), yet another URL shortifiyer. Built on Camping, a Ruby microframework, contained in a 350 line file (plus CSS and a bootstrapper for Rack). For spam prevention, it checks the URLs in SURBL and URIBL and the requesting IP in several DNS blacklists.

<del>Best viewed in any browser except Internet Explorer (position: fixed and margin: auto won't work for some reason, will fix it later)</del> Looks normal in IE7 now (added DOCTYPE to HTML output).

License: [[MIT license|license]]    
Code: <http://github.com/jou/yaurls>

# Install

For starters, you need Ruby and Camping. Can't say how you could install Ruby, but for Camping, it's easy:

    gem install camping --source http://code.whytheluckystiff.net
    
It also need `activesupport` and `nokogiri`

    gem install activesupport nokogiri

Run the Camping Server

    ~$ svn co http://svn-public.orly.ch/stuff/yaurls/ && cd yaurls
    ~/yaurls$ camping yaurls.rb

Hit localhost:3301 in the browser and you're up and running. If run that way, the app stores its data in a SQLite DB (~/.camping.db)

For deploying a copy for production, you could either use [Phusion Passenger](http://www.modrails.com/) and Apache or one of the methods in [Camping's docs](http://code.whytheluckystiff.net/camping/wiki/TheCampingServer). A Rack handler is provided (config.ru). [srs.li](http://srs.li/) uses Passenger. Just [install it](http://www.modrails.com/documentation/Users%20guide.html#_installing_phusion_passenger), point the Apache's DocumentRoot to you working copy's 'static/' directory and there you go.