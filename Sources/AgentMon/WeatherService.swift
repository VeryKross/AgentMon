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
    var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
    components.queryItems = [
      URLQueryItem(name: "latitude", value: String(place.latitude)),
      URLQueryItem(name: "longitude", value: String(place.longitude)),
      URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
      URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
      URLQueryItem(name: "timezone", value: "auto"),
    ]

    guard let url = components.url else { throw WeatherServiceError.invalidResponse }
    let (data, response) = try await session.data(from: url)
    try validate(response)
    let forecast = try JSONDecoder().decode(ForecastResponse.self, from: data)

    return WeatherSnapshot(
      location: [place.name, place.admin1].compactMap { $0 }.joined(separator: ", "),
      temperature: forecast.current.temperature,
      weatherCode: forecast.current.weatherCode,
      isDay: forecast.current.isDay == 1,
      fetchedAt: .now
    )
  }

  private func geocode(location: String) async throws -> GeocodingResult {
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

  private func validate(_ response: URLResponse) throws {
    guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
      throw WeatherServiceError.invalidResponse
    }
  }
}

private struct GeocodingResponse: Decodable {
  let results: [GeocodingResult]?
}

private struct GeocodingResult: Decodable {
  let name: String
  let admin1: String?
  let latitude: Double
  let longitude: Double
}

private struct ForecastResponse: Decodable {
  let current: CurrentWeather
}

private struct CurrentWeather: Decodable {
  let temperature: Double
  let weatherCode: Int
  let isDay: Int

  enum CodingKeys: String, CodingKey {
    case temperature = "temperature_2m"
    case weatherCode = "weather_code"
    case isDay = "is_day"
  }
}
