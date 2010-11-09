require 'resolv'
require 'timeout'

module DNSBL

  # return values:
  #   true if found on blacklist
  #   false otherwise
  def self.check(query, bl)
    begin
      Timeout.timeout(3) { Resolv.getaddress("#{query}.#{bl}") }
    rescue Exception
      false
    end
  end
  
  def self.check_uribl_black(domain)
    self.check(domain, 'multi.uribl.com') == '127.0.0.2'
  end

  def self.check_surbl(domain)
    !!self.check(domain, 'multi.surbl.org').match(/^127.0.0/)
  end

  def self.check_ip(ip)
    ip = (ip.split(/\./).reverse.join('.') rescue nil)

    threads = [
      Thread.new {
        if self.check(ip, 'sbl.spamhaus.org') != false
          'spamhaus.org'
        end
      },
      Thread.new {
        if self.check(ip, 'blacklist.spambag.org') != false
          'spambag.org'
        end
      },
      Thread.new {
        if self.check(ip, 'spews.dnsbl.sorbs.net') != false
          'spews.org'
        end
      },
      Thread.new {
        if self.check(ip, 'tor.dnsbl.sectoor.de') == '127.0.0.1'
          'Tor'
        end
      }
    ]

    values = threads.map{|a| a.value}.delete_if{|x| !x}

    if values.size > 0
      return values.first
    else
      return false
    end
  end

  # checks a second level domain
  def self.check_domain(domain)
    self.check_uribl_black(domain) or self.check_surbl(domain)
  end

  # checks a text for forbidden domains
  def self.check_text(text)
    self.get_domains_from_text(text).each do |domain|
      return domain if self.check_domain(domain)
    end
    return false
  end

  def self.get_domains_from_text(text)
    text.scan(/(?:http:\/\/|www?)\S*?([a-z0-9\-]+\.[a-z0-9\-]+)(?:\s|$|\/)/i).uniq
  end
end
