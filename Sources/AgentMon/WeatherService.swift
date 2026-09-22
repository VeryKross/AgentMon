import Foundation

enum WeatherServiceError: LocalizedError {
  case locationNotFound
  case invalidResponse

  var errorDescription: String? {
    switch self {
    case .locationNotFound:
      "That location could not be found."
    case .invalidResponse:
      "The weather service returned an invalid response."
    }
  }
}

struct WeatherService {
  private let session: URLSession

  init(session: URLSession = .shared) {
    self.session = session
  }

  func fetch(location: String) async throws -> WeatherSnapshot {
    let place = try await geocode(location: location)
    async let forecast = fetchForecast(place: place)
    async let observedCondition = fetchObservedCondition(place: place)

    let current = try await forecast
    let observation = await observedCondition

    return WeatherSnapshot(
      location: [place.name, place.admin1].compactMap { $0 }.joined(separator: ", "),
      temperature: current.temperature,
      weatherCode: current.weatherCode,
      cloudCover: current.cloudCover,
      isDay: current.isDay == 1,
      observedCondition: observation,
      fetchedAt: .now
    )
  }

  private func fetchForecast(place: GeocodingResult) async throws -> CurrentWeather {
    var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
    components.queryItems = [
      URLQueryItem(name: "latitude", value: String(place.latitude)),
      URLQueryItem(name: "longitude", value: String(place.longitude)),
      URLQueryItem(
        name: "current",
        value: "temperature_2m,weather_code,cloud_cover,is_day"
      ),
      URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
      URLQueryItem(name: "timezone", value: "auto"),
    ]

    guard let url = components.url else { throw WeatherServiceError.invalidResponse }
    let (data, response) = try await session.data(from: url)
    try validate(response)
    let forecast = try JSONDecoder().decode(ForecastResponse.self, from: data)
    return forecast.current
  }

  private func geocode(location: String) async throws -> GeocodingResult {
    if let zipCode = WeatherLocationParser.usZipCode(from: location),
      let place = await geocodeUSZip(zipCode)
    {
      return place
    }

    var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
    components.queryItems = [
      URLQueryItem(name: "name", value: location),
      URLQueryItem(name: "count", value: "1"),
      URLQueryItem(name: "language", value: "en"),
      URLQueryItem(name: "format", value: "json"),
    ]

    guard let url = components.url else { throw WeatherServiceError.invalidResponse }
    let (data, response) = try await session.data(from: url)
    try validate(response)
    let result = try JSONDecoder().decode(GeocodingResponse.self, from: data)
    guard let place = result.results?.first else {
      throw WeatherServiceError.locationNotFound
    }
    return place
  }

  private func geocodeUSZip(_ zipCode: String) async -> GeocodingResult? {
    guard let url = URL(string: "https://api.zippopotam.us/us/\(zipCode)") else {
      return nil
    }

    do {
      let (data, response) = try await session.data(from: url)
      try validate(response)
      let result = try JSONDecoder().decode(USZipResponse.self, from: data)
      guard let place = result.places.first,
        let latitude = Double(place.latitude),
        let longitude = Double(place.longitude)
      else {
        return nil
      }

      return GeocodingResult(
        name: place.name,
        admin1: place.state,
        countryCode: result.countryCode,
        latitude: latitude,
        longitude: longitude
      )
    } catch {
      return nil
    }
  }

  private func fetchObservedCondition(place: GeocodingResult) async -> ObservedWeatherCondition? {
    guard place.countryCode == "US" else { return nil }

    do {
      let point: NWSPointResponse = try await fetchNWS(
        URL(string: "https://api.weather.gov/points/\(place.latitude),\(place.longitude)")!
      )
      let stations: NWSStationsResponse = try await fetchNWS(point.properties.observationStations)

      for station in stations.features.prefix(3) {
        let observation: NWSObservationResponse = try await fetchNWS(
          station.id
            .appendingPathComponent("observations")
            .appendingPathComponent("latest")
        )
        guard observation.properties.isFresh else { continue }
        if let condition = ObservedWeatherCondition(
          description: observation.properties.textDescription
        ) {
          return condition
        }
      }
    } catch {
      return nil
    }

    return nil
  }

  private func fetchNWS<Response: Decodable>(_ url: URL) async throws -> Response {
    var request = URLRequest(url: url)
    request.setValue(
      "AgentMon/0.1.3 (https://github.com/VeryKross/AgentMon)",
      forHTTPHeaderField: "User-Agent"
    )
    request.setValue("application/geo+json", forHTTPHeaderField: "Accept")

    let (data, response) = try await session.data(for: request)
    try validate(response)
    return try JSONDecoder().decode(Response.self, from: data)
  }

  private func validate(_ response: URLResponse) throws {
    guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
      throw WeatherServiceError.invalidResponse
    }
  }
}

private struct GeocodingResponse: Decodable {
  let results: [GeocodingResult]?
}

private struct USZipResponse: Decodable {
  let countryCode: String
  let places: [Place]

  enum CodingKeys: String, CodingKey {
    case countryCode = "country abbreviation"
    case places
  }

  struct Place: Decodable {
    let name: String
    let state: String
    let latitude: String
    let longitude: String

    enum CodingKeys: String, CodingKey {
      case name = "place name"
      case state
      case latitude
      case longitude
    }
  }
}

private struct GeocodingResult: Decodable {
  let name: String
  let admin1: String?
  let countryCode: String
  let latitude: Double
  let longitude: Double

  enum CodingKeys: String, CodingKey {
    case name
    case admin1
    case countryCode = "country_code"
    case latitude
    case longitude
  }
}

private struct ForecastResponse: Decodable {
  let current: CurrentWeather
}

private struct CurrentWeather: Decodable {
  let temperature: Double
  let weatherCode: Int
  let cloudCover: Double
  let isDay: Int

  enum CodingKeys: String, CodingKey {
    case temperature = "temperature_2m"
    case weatherCode = "weather_code"
    case cloudCover = "cloud_cover"
    case isDay = "is_day"
  }
}

private struct NWSPointResponse: Decodable {
  let properties: Properties

  struct Properties: Decodable {
    let observationStations: URL
  }
}

private struct NWSStationsResponse: Decodable {
  let features: [Station]

  struct Station: Decodable {
    let id: URL
  }
}

private struct NWSObservationResponse: Decodable {
  let properties: Properties

  struct Properties: Decodable {
    let timestamp: String
    let textDescription: String

    var isFresh: Bool {
      guard let date = ISO8601DateFormatter().date(from: timestamp) else { return false }
      return abs(date.timeIntervalSinceNow) <= 2 * 60 * 60
    }
  }
}

enum WeatherLocationParser {
  static func usZipCode(from value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let firstFive = String(trimmed.prefix(5))

    guard firstFive.count == 5,
      firstFive.allSatisfy(\.isNumber),
      trimmed.count == 5
        || (trimmed.count == 10 && trimmed[trimmed.index(trimmed.startIndex, offsetBy: 5)] == "-")
    else {
      return nil
    }

    return firstFive
  }
}
