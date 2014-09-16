require "sinatra"
require "oauth"
require "json"

enable :sessions

PCO_KEY = ENV["PCO_KEY"]
PCO_SECRET = ENV["PCO_SECRET"]

before %r{^(?!/callback)} do
  @access_token = session[:access_token]
  next if @access_token

  oauth = OAuth::Consumer.new PCO_KEY, PCO_SECRET, site: "https://planningcenteronline.com"
  request_token = oauth.get_request_token oauth_callback: "#{request.base_url}/callback"
  session[:request_token] = request_token
  redirect to request_token.authorize_url
end

get "/callback" do
  request_token = session[:request_token]
  @access_token = request_token.get_access_token oauth_verifier: params[:oauth_verifier]
  session[:access_token] = @access_token

  redirect to "/"
end

def api_hash object
  response = @access_token.get "/#{object}.json"
  body = JSON.parse response.body
  body[object.to_s]
end

get "/songs" do
  songs_without_attachments = "<h1>Songs without attachments</h1>"

  songs = api_hash(:songs)
  songs.each do |song|
    next if song["attachments"].empty?
    songs_without_attachments += "<li>#{song["title"]}</li>"
  end

  songs_without_attachments
end

get "/" do
  "<a href='/songs'>Songs without attachments</a>"
end
