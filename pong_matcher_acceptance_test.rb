require "minitest/autorun"
require "json"

class PongMatcherAcceptance < Minitest::Test
  def setup
    @host = ENV.fetch("HOST", "http://localhost:3000")
    Admin.new(@host).clear
  end

  def test_that_lonely_player_cannot_be_matched
    williams = Client.new(@host, "williams")
    match_request = williams.request_match

    refute match_request.fulfilled?, "a single player shouldn't be matched"
  end

  def test_that_two_players_can_be_matched
    williams = Client.new(@host, "williams")
    sharapova = Client.new(@host, "sharapova")

    request_1 = williams.request_match
    request_2 = sharapova.request_match

    assert request_1.fulfilled?,
      ["Williams didn't receive notification of her match!",
       request_1.last_response.body].join("\n")
    assert request_2.fulfilled?,
      "Sharapova didn't receive notification of her match!"
  end

  def test_that_entering_result_ensures_match_with_new_player
    williams = Client.new(@host, "williams")
    sharapova = Client.new(@host, "sharapova")
    navratilova = Client.new(@host, "navratilova")

    williams_request_id = SecureRandom.uuid

    williams_request = williams.request_match(match_request_id: williams_request_id)
    sharapova.request_match

    williams.loses_to(sharapova, match_id: williams_request.match_id)

    williams_new_request = williams.request_match
    sharapova_new_request = sharapova.request_match
    navratilova_request = navratilova.request_match

    assert williams_new_request.fulfilled?,
      "Williams didn't receive notification of her match!"

    refute sharapova_new_request.fulfilled?,
      ["Sharapova shouldn't have a match, because she just played Williams!",
       "Expected Navratilova to be matched with Williams.",
       sharapova_new_request.last_response.body].join("\n")

    assert navratilova_request.fulfilled?,
      "Navratilova didn't receive notification of her match!"
  end
end

require "faraday"

class Admin
  def initialize(host)
    @http = Faraday.new(url: host)
  end

  def clear
    @http.delete("/all")
  end
end

class Client
  attr_reader :id

  def initialize(host, id)
    @http = Faraday.new(url: host)
    @id = id
  end

  def request_match(match_request_id: SecureRandom.uuid)
    MatchRequest.new(match_request_id, http, id).tap(&:call)
  end

  def loses_to(winner, options)
    enter_result(
      match_id: options.fetch(:match_id),
      winner: winner,
      loser: self
    )
  end

  private

  def enter_result(match_id: nil, winner: nil, loser: nil)
    nil_arg = {match_id: match_id, winner: winner}.detect { |name, arg| arg.nil? }
    if nil_arg
      raise ArgumentError, "#{nil_arg[0]} is nil!"
    else
      response = http.post("/results", JSON.generate(match_id: match_id, winner: winner.id, loser: loser.id))
      if response.status != 201
        raise ["POST /results responded with #{response.status}",
               response.body].join("\n")
      end
    end
  end

  attr_reader :http
end

require "securerandom"

class MatchRequest
  attr_reader :last_response

  def initialize(id, http, player_id)
    @id = id
    @http = http
    @player_id = player_id
  end

  def call
    self.last_response = http.put(path, JSON.generate(player: player_id))
    if last_response.status != 200
      raise ["PUT #{path} responded with #{last_response.status}",
             last_response.body].join("\n")
    end
    last_response
  end

  def fulfilled?
    self.last_response = get(path)
    last_response.status == 200 && has_match_id?(last_response)
  end

  def match_id
    self.last_response = get(path)
    extract(last_response, "match_id")
  end

  private

  attr_writer :last_response

  def get(path)
    http.get(path).tap do |response|
      if response.status >= 400 && response.status != 404
        raise ["GET #{path} responded with #{response.status}",
               response.body].join("\n")
      end
    end
  end

  def has_match_id?(response)
    match_id = extract(response, "match_id")
    match_id != "" && !match_id.nil?
  end

  def extract(response, attribute)
    JSON.parse(response.body)[attribute]
  rescue JSON::ParserError => e
    raise "Invalid JSON: #{response.body}\n#{e.message}"
  end

  def path
    "/match_requests/#{id}"
  end

  attr_reader :id, :http, :player_id
end