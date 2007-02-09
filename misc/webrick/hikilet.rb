#!/usr/bin/ruby -Ke
# $Id: hikilet.rb,v 1.4 2007-02-09 21:39:47 znz Exp $
# Copyright (C) 2005-2007 Kazuhiro NISHIYAMA

require 'hiki/config'
require 'webrick/httpservlet/abstract'

class Hikilet < WEBrick::HTTPServlet::AbstractServlet
  DEFOUT = Object.new
  def DEFOUT.write(s)
    (Thread.current[:defout]||::STDOUT) << s.to_s
  end
  $stdout = DEFOUT

  class CGI
    def initialize(req, res)
      @req, @res = req, res
      @params = nil
      @cookies = nil
    end

    def request_method
      @req.request_method
    end

    def header(headers)
      headers.each do |k, v|
        case k
        when 'cookie'
          @res['Set-Cookie'] = v
        when 'type'
          @res['Content-Type'] = v
        else
          @res[k] = v
        end
      end
      '' # print nothing
    end

    def params
      return @params if @params
      @params = Hash.new([])
      @req.query.each do |k,v|
        @params[k] = [v]
      end
      @params
    end

    def [](key)
      params[key][0]
    end

    def cookies
      return @cookies if @cookies
      @cookies = Hash.new([])
      @req.cookies.each do |cookie|
        @cookies[cookie.name] = [cookie.value]
      end
      @cookies
    end
  end

  def do_GET(req, res)
    Thread.current[:defout] = ''
    # ugly hack (thread unsafe)
    saved_HTTP_ACCEPT_LANGUAGE = ENV['HTTP_ACCEPT_LANGUAGE']
    ENV['HTTP_ACCEPT_LANGUAGE'] = req['Accept-Language']
    conf = Hiki::Config::new
    ENV['HTTP_ACCEPT_LANGUAGE'] = saved_HTTP_ACCEPT_LANGUAGE
    cgi = CGI::new(req, res)
    db = Hiki::HikiDB::new( conf )
    db.open_db {
      cmd = Hiki::Command::new( cgi, db, conf )
      cmd.dispatch
    }
    res.body, Thread.current[:defout] = Thread.current[:defout], nil
    if res['location']
      res.status = 302
    end
  end

  def do_HEAD(req, res)
      do_GET(req, res)
  end

  def do_POST(req, res)
    do_GET(req, res)
  end
end

if __FILE__ == $0
  require 'webrick'
  require 'logger'

  conf = Hiki::Config::new
  base_url = URI.parse(conf.base_url)
  theme_url = base_url + conf.theme_url
  theme_path = conf.theme_path
  conf = nil
  ENV['SERVER_NAME'] ||= base_url.host
  ENV['SERVER_PORT'] ||= base_url.port.to_s
  logger = WEBrick::Log::new(STDERR, WEBrick::Log::INFO)
  server = WEBrick::HTTPServer.new({
    :Port => base_url.port,
    :Logger => logger,
  })

  if FileTest::symlink?( __FILE__ )
    org_path = File::dirname( File::expand_path( File::readlink( __FILE__ ) ) )
  else
    org_path = File::dirname( File::expand_path( __FILE__ ) )
  end
  $:.unshift( org_path.untaint, "#{org_path.untaint}/hiki" )
  $:.delete(".") if File.writable?(".")

  server.mount(base_url.path, Hikilet)
  if base_url.host == theme_url.host && base_url.port == theme_url.port
    server.mount(theme_url.path, WEBrick::HTTPServlet::FileHandler, theme_path)
  end

  trap("INT") {server.shutdown}
  server.start
end
