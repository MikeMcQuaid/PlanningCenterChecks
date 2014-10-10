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

def api_hash object, parameters={}
  endpoint = "/#{object}.json"
  parameters.each do |key, value|
    start = parameters.keys.first == key ? "?" : "&"
    endpoint += "#{start}#{key}=#{value}"
  end
  response = @access_token.get endpoint
  body = JSON.parse response.body
  body[object.to_s]
end

def song_and_arrangement_attachments song
  attachments = song["attachments"]

  song["arrangements"].to_a.each do |arrangement|
    attachments += arrangement["attachments"]
  end

  attachments
end

get "/songs" do
  songs_without_attachments = "<h1>Songs without attachments</h1>"

  songs = api_hash(:songs, include_arrangements: true)
  songs.each do |song|
    next if song_and_arrangement_attachments(song).empty?
    songs_without_attachments += "<li>#{song["title"]}</li>"
  end

  songs_without_attachments
end

get "/" do
  "<a href='/songs'>Songs without attachments</a>"
end
