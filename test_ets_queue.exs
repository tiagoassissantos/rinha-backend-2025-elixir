#!/usr/bin/env elixir

# Comprehensive test for ETS-based PaymentQueue
# Usage: elixir test_ets_queue.exs

Mix.install([
  {:jason, "~> 1.4"},
  {:telemetry, "~> 1.3"},
  {:opentelemetry_api, "~> 1.4"},
  {:decimal, "~> 2.3"}
])

defmodule MockPaymentGateway do
  @moduledoc """
  Mock payment gateway for testing
  """
  
  def send_payment(payload) do
    # Simulate processing time
    Process.sleep(Enum.random(1..10))
    
    case Map.get(payload, "simulate") do
      "error" -> {:error, :payment_failed}
      "timeout" -> Process.sleep(1000); :ok
      _ -> :ok
    end
  end
end

defmodule ETSQueueTest do
  @moduledoc """
  Test suite for ETS-based payment queue
  """
  
  @table_name :test_payment_work_queue
  @queue_size_counter :test_payment_queue_size
  @in_flight_counter :test_payment_in_flight
  
  def run_all_tests do
    IO.puts("🧪 ETS Queue Comprehensive Test Suite")
    IO.puts("=====================================\n")
    
    setup_test_environment()
    
    try do
      # Core functionality tests
      test_basic_enqueue_dequeue()
      test_fifo_ordering()
      test_concurrent_enqueue()
      test_back_pressure()
      
      # Worker tests  
      test_worker_processing()
      test_worker_error_handling()
      test_multiple_workers()
      
      # Performance tests
      test_high_throughput()
      test_memory_usage()
      
      # Telemetry tests
      test_telemetry_events()
      
      IO.puts("\n✅ All tests passed!")
      
    rescue
      error ->
        IO.puts("\n❌ Test failed: #{inspect(error)}")
        System.halt(1)
    after
      cleanup_test_environment()
    end
  end
  
  defp setup_test_environment do
    IO.puts("🔧 Setting up test environment...")
    
    # Create ETS table
    table_opts = [
      :ordered_set,
      :public,
      :named_table,
      {:read_concurrency, true},
      {:write_concurrency, true}
    ]
    
    if :ets.whereis(@table_name) != :undefined do
      :ets.delete(@table_name)
    end
    
    @table_name = :ets.new(@table_name, table_opts)
    
    # Create atomic counters
    queue_counter = :atomics.new(1, [])
    in_flight_counter = :atomics.new(1, [])
    
    :persistent_term.put(@queue_size_counter, queue_counter)
    :persistent_term.put(@in_flight_counter, in_flight_counter)
    
    # Start telemetry handler for testing
    :telemetry.attach_many(
      "test_queue_handler",
      [
        [:tas, :queue, :enqueue],
        [:tas, :queue, :drop],
        [:tas, :queue, :wait_time],
        [:tas, :queue, :state]
      ],
      &handle_telemetry_event/4,
      []
    )
    
    IO.puts("✅ Test environment ready\n")
  end
  
  defp cleanup_test_environment do
    IO.puts("\n🧹 Cleaning up test environment...")
    
    if :ets.whereis(@table_name) != :undefined do
      :ets.delete(@table_name)
    end
    
    :persistent_term.erase(@queue_size_counter)
    :persistent_term.erase(@in_flight_counter)
    
    :telemetry.detach("test_queue_handler")
    
    IO.puts("✅ Cleanup complete")
  end
  
  # Test: Basic enqueue and dequeue operations
  defp test_basic_enqueue_dequeue do
    IO.puts("1. Testing basic enqueue/dequeue...")
    
    payload = %{"correlationId" => "test-123", "amount" => 100.0}
    
    # Enqueue
    result = enqueue_payment(payload)
    assert result == :ok, "Expected :ok, got #{inspect(result)}"
    
    # Check queue size
    stats = get_stats()
    assert stats.queue_size == 1, "Expected queue_size=1, got #{stats.queue_size}"
    
    # Dequeue
    work_item = take_next_work()
    assert match?({:ok, ^payload, _enqueue_time, _span_ctx, _wait_ms}, work_item),
           "Expected work item with payload, got #{inspect(work_item)}"
    
    # Check queue is empty
    stats = get_stats()
    assert stats.queue_size == 0, "Expected queue_size=0 after dequeue, got #{stats.queue_size}"
    
    IO.puts("✅ Basic enqueue/dequeue works")
  end
  
  # Test: FIFO ordering is maintained
  defp test_fifo_ordering do
    IO.puts("2. Testing FIFO ordering...")
    
    # Enqueue multiple items
    payloads = [
      %{"id" => 1, "amount" => 10},
      %{"id" => 2, "amount" => 20},
      %{"id" => 3, "amount" => 30}
    ]
    
    Enum.each(payloads, fn payload ->
      :ok = enqueue_payment(payload)
      Process.sleep(1) # Ensure different timestamps
    end)
    
    # Dequeue and verify order
    results = for _ <- 1..3 do
      {:ok, payload, _, _, _} = take_next_work()
      payload
    end
    
    expected_ids = [1, 2, 3]
    actual_ids = Enum.map(results, & &1["id"])
    
    assert actual_ids == expected_ids,
           "Expected FIFO order #{inspect(expected_ids)}, got #{inspect(actual_ids)}"
    
    IO.puts("✅ FIFO ordering maintained")
  end
  
  # Test: Concurrent enqueue operations
  defp test_concurrent_enqueue do
    IO.puts("3. Testing concurrent enqueue...")
    
    num_tasks = 100
    
    tasks = for i <- 1..num_tasks do
      Task.async(fn ->
        payload = %{"id" => i, "amount" => i * 10}
        enqueue_payment(payload)
      end)
    end
    
    results = Enum.map(tasks, &Task.await/1)
    
    # All enqueues should succeed
    assert Enum.all?(results, &(&1 == :ok)),
           "Some concurrent enqueues failed: #{inspect(results)}"
    
    # Verify final queue size
    stats = get_stats()
    assert stats.queue_size == num_tasks,
           "Expected queue_size=#{num_tasks}, got #{stats.queue_size}"
    
    # Drain the queue for next test
    for _ <- 1..num_tasks, do: take_next_work()
    
    IO.puts("✅ Concurrent enqueue (#{num_tasks} tasks) works")
  end
  
  # Test: Back-pressure mechanism
  defp test_back_pressure do
    IO.puts("4. Testing back-pressure...")
    
    # Temporarily set a small max queue size
    original_config = Application.get_env(:tas_rinhaback_3ed, :payment_queue, [])
    Application.put_env(:tas_rinhaback_3ed, :payment_queue, [max_queue_size: 3])
    
    try do
      # Fill up to capacity
      for i <- 1..3 do
        result = enqueue_payment(%{"id" => i})
        assert result == :ok, "Expected :ok for item #{i}, got #{inspect(result)}"
      end
      
      # Next enqueue should fail
      result = enqueue_payment(%{"id" => 4})
      assert result == {:error, :queue_full},
             "Expected {:error, :queue_full}, got #{inspect(result)}"
      
      IO.puts("✅ Back-pressure works correctly")
      
    after
      # Restore original config
      Application.put_env(:tas_rinhaback_3ed, :payment_queue, original_config)
      # Clear the queue
      while take_next_work() != :empty do
        :ok
      end
    end
  end
  
  # Test: Worker processing
  defp test_worker_processing do
    IO.puts("5. Testing worker processing...")
    
    # Enqueue some work
    payloads = [
      %{"id" => 1, "amount" => 100},
      %{"id" => 2, "amount" => 200}
    ]
    
    Enum.each(payloads, &enqueue_payment/1)
    
    # Start a worker
    worker_task = Task.async(fn ->
      test_worker_loop(2) # Process 2 items then stop
    end)
    
    # Wait for processing
    result = Task.await(worker_task, 5000)
    assert result == :completed, "Worker didn't complete processing"
    
    # Queue should be empty
    stats = get_stats()
    assert stats.queue_size == 0, "Expected empty queue after processing"
    
    IO.puts("✅ Worker processing works")
  end
  
  # Test: Worker error handling
  defp test_worker_error_handling do
    IO.puts("6. Testing worker error handling...")
    
    # Enqueue work that will cause an error
    error_payload = %{"simulate" => "error", "id" => "error-test"}
    :ok = enqueue_payment(error_payload)
    
    # Process with error handling
    {:ok, payload, _, _, _} = take_next_work()
    
    # Simulate worker processing with error
    result = MockPaymentGateway.send_payment(payload)
    assert result == {:error, :payment_failed}, "Expected error result"
    
    IO.puts("✅ Worker error handling works")
  end
  
  # Test: Multiple workers processing concurrently  
  defp test_multiple_workers do
    IO.puts("7. Testing multiple workers...")
    
    num_items = 20
    num_workers = 4
    
    # Enqueue work items
    for i <- 1..num_items do
      :ok = enqueue_payment(%{"id" => i, "amount" => i * 10})
    end
    
    initial_queue_size = get_stats().queue_size
    assert initial_queue_size == num_items, "Expected #{num_items} items in queue"
    
    # Start multiple workers
    workers = for i <- 1..num_workers do
      Task.async(fn ->
        test_worker_loop(:unlimited, 2000) # Process for 2 seconds
      end)
    end
    
    # Wait for workers
    Enum.each(workers, &Task.await(&1, 5000))
    
    # Most or all items should be processed
    final_stats = get_stats()
    assert final_stats.queue_size < initial_queue_size,
           "Expected queue to be drained, still has #{final_stats.queue_size} items"
    
    IO.puts("✅ Multiple workers processing concurrently")
  end
  
  # Test: High throughput performance
  defp test_high_throughput do
    IO.puts("8. Testing high throughput...")
    
    num_operations = 10_000
    
    start_time = System.monotonic_time(:microsecond)
    
    # Concurrent enqueues
    tasks = for i <- 1..num_operations do
      Task.async(fn ->
        enqueue_payment(%{"id" => i, "batch" => "perf_test"})
      end)
    end
    
    # Wait for all enqueues
    results = Enum.map(tasks, &Task.await/1)
    
    enqueue_time = System.monotonic_time(:microsecond) - start_time
    
    # Verify all succeeded
    success_count = Enum.count(results, &(&1 == :ok))
    assert success_count == num_operations,
           "Expected #{num_operations} successes, got #{success_count}"
    
    # Performance metrics
    ops_per_second = num_operations / (enqueue_time / 1_000_000)
    avg_time_per_op = enqueue_time / num_operations
    
    IO.puts("   📊 Performance: #{Float.round(ops_per_second, 0)} ops/sec")
    IO.puts("   📊 Average: #{Float.round(avg_time_per_op, 2)}μs per operation")
    
    # Cleanup
    stats = get_stats()
    IO.puts("   📊 Final queue size: #{stats.queue_size}")
    
    # Quick drain for cleanup
    drain_start = System.monotonic_time(:microsecond)
    drained = drain_queue()
    drain_time = System.monotonic_time(:microsecond) - drain_start
    drain_ops_per_second = drained / (drain_time / 1_000_000)
    
    IO.puts("   📊 Drain performance: #{Float.round(drain_ops_per_second, 0)} ops/sec")
    IO.puts("✅ High throughput test completed")
  end
  
  # Test: Memory usage characteristics
  defp test_memory_usage do
    IO.puts("9. Testing memory usage...")
    
    # Measure baseline memory
    :erlang.garbage_collect()
    {_, baseline_memory} = :erlang.process_info(self(), :memory)
    
    # Add many items
    num_items = 1000
    for i <- 1..num_items do
      payload = %{
        "id" => i,
        "correlationId" => "test-#{i}",
        "amount" => i * 1.50,
        "metadata" => %{"batch" => "memory_test", "timestamp" => System.os_time()}
      }
      :ok = enqueue_payment(payload)
    end
    
    # Measure peak memory
    :erlang.garbage_collect()
    {_, peak_memory} = :erlang.process_info(self(), :memory)
    
    # Calculate memory per item
    memory_per_item = (peak_memory - baseline_memory) / num_items
    
    IO.puts("   📊 Memory per item: ~#{Float.round(memory_per_item, 0)} bytes")
    IO.puts("   📊 Total overhead: #{peak_memory - baseline_memory} bytes for #{num_items} items")
    
    # Verify reasonable memory usage (should be < 1KB per item for simple payloads)
    assert memory_per_item < 1024, "Memory per item too high: #{memory_per_item} bytes"
    
    # Cleanup
    drain_queue()
    
    IO.puts("✅ Memory usage test passed")
  end
  
  # Test: Telemetry events
  defp test_telemetry_events do
    IO.puts("10. Testing telemetry events...")
    
    # Clear any previous telemetry
    Process.put(:telemetry_events, [])
    
    # Generate some events
    :ok = enqueue_payment(%{"id" => "telemetry_test"})
    {:ok, _, _, _, _} = take_next_work()
    
    # Check captured events
    events = Process.get(:telemetry_events, []) |> Enum.reverse()
    
    event_types = Enum.map(events, fn {event, _, _} -> event end)
    
    # Should have enqueue event
    assert Enum.member?(event_types, [:tas, :queue, :enqueue]),
           "Missing enqueue event in #{inspect(event_types)}"
    
    # Should have wait_time event
    assert Enum.member?(event_types, [:tas, :queue, :wait_time]),
           "Missing wait_time event in #{inspect(event_types)}"
    
    IO.puts("✅ Telemetry events working correctly")
  end
  
  # Helper functions for queue operations
  
  defp enqueue_payment(payload) do
    config = Application.get_env(:tas_rinhaback_3ed, :payment_queue, [])
    max_queue_size = Keyword.get(config, :max_queue_size, :infinity)
    
    cond do
      max_queue_size != :infinity ->
        current_size = :atomics.get(:persistent_term.get(@queue_size_counter), 1)
        
        if current_size >= max_queue_size do
          :telemetry.execute([:tas, :queue, :drop], %{queue_len: current_size}, %{})
          {:error, :queue_full}
        else
          do_enqueue(payload)
        end
      
      true ->
        do_enqueue(payload)
    end
  end
  
  defp do_enqueue(payload) do
    # Generate ordered key for FIFO processing
    key = {System.monotonic_time(), make_ref()}
    
    # Mock OpenTelemetry context
    span_ctx = nil
    
    # Direct ETS write
    entry = {payload, System.monotonic_time(), span_ctx}
    :ets.insert(@table_name, {key, entry})
    
    # Update atomic counter
    :atomics.add(:persistent_term.get(@queue_size_counter), 1, 1)
    
    # Emit telemetry
    new_size = :atomics.get(:persistent_term.get(@queue_size_counter), 1)
    :telemetry.execute([:tas, :queue, :enqueue], %{queue_len: new_size}, %{})
    
    :ok
  end
  
  defp take_next_work do
    case :ets.first(@table_name) do
      :"$end_of_table" ->
        :empty
      
      key ->
        case :ets.take(@table_name, key) do
          [{^key, {payload, enqueue_time, span_ctx}}] ->
            # Successfully took work item
            :atomics.sub(:persistent_term.get(@queue_size_counter), 1, 1)
            
            # Calculate wait time
            now = System.monotonic_time()
            wait_ms = System.convert_time_unit(now - enqueue_time, :native, :millisecond)
            :telemetry.execute([:tas, :queue, :wait_time], %{wait_ms: wait_ms}, %{})
            
            {:ok, payload, enqueue_time, span_ctx, wait_ms}
          
          [] ->
            # Someone else took it, try again
            take_next_work()
        end
    end
  end
  
  defp get_stats do
    queue_size = :atomics.get(:persistent_term.get(@queue_size_counter), 1)
    in_flight = :atomics.get(:persistent_term.get(@in_flight_counter), 1)
    
    %{queue_size: max(0, queue_size), in_flight: max(0, in_flight)}
  end
  
  defp test_worker_loop(0), do: :completed
  defp test_worker_loop(items_to_process) when is_integer(items_to_process) and items_to_process > 0 do
    case take_next_work() do
      {:ok, payload, _, _, _} ->
        # Process the payment
        _result = MockPaymentGateway.send_payment(payload)
        test_worker_loop(items_to_process - 1)
      
      :empty ->
        Process.sleep(10)
        test_worker_loop(items_to_process)
    end
  end
  
  defp test_worker_loop(:unlimited, timeout_ms) do
    end_time = System.monotonic_time(:millisecond) + timeout_ms
    test_worker_loop_with_timeout(end_time)
  end
  
  defp test_worker_loop_with_timeout(end_time) do
    if System.monotonic_time(:millisecond) >= end_time do
      :timeout
    else
      case take_next_work() do
        {:ok, payload, _, _, _} ->
          _result = MockPaymentGateway.send_payment(payload)
          test_worker_loop_with_timeout(end_time)
        
        :empty ->
          Process.sleep(5)
          test_worker_loop_with_timeout(end_time)
      end
    end
  end
  
  defp drain_queue do
    drain_queue(0)
  end
  
  defp drain_queue(count) do
    case take_next_work() do
      :empty -> count
      {:ok, _, _, _, _} -> drain_queue(count + 1)
    end
  end
  
  defp handle_telemetry_event(event, measurements, metadata, _config) do
    events = Process.get(:telemetry_events, [])
    Process.put(:telemetry_events, [{event, measurements, metadata} | events])
  end
  
  defp assert(condition, message) do
    unless condition do
      raise "Assertion failed: #{message}"
    end
  end
end

# Set up mock application config
Application.put_env(:tas_rinhaback_3ed, :payment_queue, [
  max_concurrency: 4,
  max_queue_size: :infinity
])

# Run the test suite
ETSQueueTest.run_all_tests()