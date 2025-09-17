#!/usr/bin/env elixir

# Simple test script to validate optimized payment endpoint
# Usage: elixir test_optimized.exs

Mix.install([
  {:req, "~> 0.5.0"},
  {:jason, "~> 1.4"}
])

defmodule OptimizedTest do
  def run do
    base_url = "http://localhost:9999"
    
    IO.puts("Testing optimized payment endpoint...")
    IO.puts("Make sure the server is running on #{base_url}")
    IO.puts("")
    
    # Test health endpoint first
    test_health(base_url)
    
    # Test optimized payments endpoint
    test_payments(base_url)
    
    # Test payments summary
    test_payments_summary(base_url)
    
    IO.puts("\nAll tests completed!")
  end
  
  defp test_health(base_url) do
    IO.puts("1. Testing health endpoint...")
    
    case Req.get("#{base_url}/health") do
      {:ok, %{status: 200, body: %{"status" => "ok"}}} ->
        IO.puts("✓ Health check passed")
      
      {:ok, response} ->
        IO.puts("✗ Health check failed: #{inspect(response)}")
      
      {:error, reason} ->
        IO.puts("✗ Health check error: #{inspect(reason)}")
    end
  end
  
  defp test_payments(base_url) do
    IO.puts("\n2. Testing optimized payments endpoint...")
    
    # Test with valid payload
    payload = %{
      "correlationId" => "123e4567-e89b-12d3-a456-426614174000",
      "amount" => 100.50
    }
    
    headers = [{"content-type", "application/json"}]
    body = Jason.encode!(payload)
    
    case Req.post("#{base_url}/payments", body: body, headers: headers) do
      {:ok, %{status: 204, body: ""}} ->
        IO.puts("✓ Payments endpoint returns 204 with empty body (optimized)")
      
      {:ok, response} ->
        IO.puts("✗ Unexpected payments response: #{inspect(response)}")
      
      {:error, reason} ->
        IO.puts("✗ Payments request error: #{inspect(reason)}")
    end
    
    # Test with invalid JSON to check parser limits
    IO.puts("   Testing with minimal payload...")
    minimal_payload = %{"test" => "data"}
    minimal_body = Jason.encode!(minimal_payload)
    
    case Req.post("#{base_url}/payments", body: minimal_body, headers: headers) do
      {:ok, %{status: 204}} ->
        IO.puts("✓ Minimal payload accepted (validation disabled)")
      
      {:ok, response} ->
        IO.puts("? Minimal payload response: #{response.status}")
      
      {:error, reason} ->
        IO.puts("✗ Minimal payload error: #{inspect(reason)}")
    end
  end
  
  defp test_payments_summary(base_url) do
    IO.puts("\n3. Testing payments summary endpoint...")
    
    # Test with valid query params
    from_date = "2024-01-01T00:00:00Z"
    to_date = "2024-12-31T23:59:59Z"
    url = "#{base_url}/payments-summary?from=#{URI.encode(from_date)}&to=#{URI.encode(to_date)}"
    
    case Req.get(url) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        if Map.has_key?(body, "default") and Map.has_key?(body, "fallback") do
          IO.puts("✓ Payments summary returns expected structure")
        else
          IO.puts("? Payments summary structure: #{inspect(body)}")
        end
      
      {:ok, response} ->
        IO.puts("? Payments summary response: #{inspect(response)}")
      
      {:error, reason} ->
        IO.puts("✗ Payments summary error: #{inspect(reason)}")
    end
    
    # Test with missing params (should return 400)
    case Req.get("#{base_url}/payments-summary") do
      {:ok, %{status: 400, body: %{"error" => "invalid_request"}}} ->
        IO.puts("✓ Missing params properly rejected with 400")
      
      {:ok, response} ->
        IO.puts("? Missing params response: #{inspect(response)}")
      
      {:error, reason} ->
        IO.puts("✗ Missing params test error: #{inspect(reason)}")
    end
  end
  
  defp benchmark_payments(base_url) do
    IO.puts("\n4. Basic performance test...")
    
    payload = %{"test" => "data"}
    headers = [{"content-type", "application/json"}]
    body = Jason.encode!(payload)
    
    # Warmup
    Req.post("#{base_url}/payments", body: body, headers: headers)
    
    # Simple benchmark
    start_time = System.monotonic_time(:microsecond)
    
    1..100
    |> Enum.map(fn _ ->
      Task.async(fn ->
        Req.post("#{base_url}/payments", body: body, headers: headers)
      end)
    end)
    |> Enum.map(&Task.await/1)
    
    end_time = System.monotonic_time(:microsecond)
    duration_ms = (end_time - start_time) / 1000
    
    IO.puts("✓ 100 concurrent requests completed in #{Float.round(duration_ms, 2)}ms")
    IO.puts("  Average: #{Float.round(duration_ms/100, 2)}ms per request")
  end
end

# Run tests
OptimizedTest.run()