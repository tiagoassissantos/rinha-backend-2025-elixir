#!/usr/bin/env elixir

# Syntax validation script for ETS queue implementation
# Usage: elixir validate_syntax.exs

defmodule SyntaxValidator do
  def validate_all do
    IO.puts("🔍 Validating ETS Queue Implementation Syntax")
    IO.puts("=" |> String.duplicate(50))
    
    files_to_validate = [
      "lib/tas_rinhaback3ed/services/payment_queue.ex",
      "lib/tas_rinhaback3ed/controllers/payment_controller.ex", 
      "lib/tas_rinhaback3ed/controllers/health_controller.ex",
      "lib/tas_rinhaback3ed/router.ex"
    ]
    
    results = Enum.map(files_to_validate, &validate_file/1)
    
    IO.puts("\n📊 Summary:")
    success_count = Enum.count(results, & &1)
    total_count = length(results)
    
    if success_count == total_count do
      IO.puts("✅ All #{total_count} files passed syntax validation!")
      System.halt(0)
    else
      failed_count = total_count - success_count
      IO.puts("❌ #{failed_count} out of #{total_count} files failed validation")
      System.halt(1)
    end
  end
  
  defp validate_file(file_path) do
    IO.write("Validating #{file_path}... ")
    
    case File.read(file_path) do
      {:ok, content} ->
        case Code.string_to_quoted(content, file: file_path) do
          {:ok, _ast} ->
            IO.puts("✅ OK")
            true
            
          {:error, {line, error_info, token}} ->
            IO.puts("❌ SYNTAX ERROR")
            IO.puts("   Line #{line}: #{Exception.format_parse_error(error_info, token)}")
            false
            
          {:error, error} ->
            IO.puts("❌ PARSE ERROR")  
            IO.puts("   #{inspect(error)}")
            false
        end
        
      {:error, :enoent} ->
        IO.puts("❌ FILE NOT FOUND")
        false
        
      {:error, reason} ->
        IO.puts("❌ READ ERROR: #{reason}")
        false
    end
  end
  
  def validate_ets_concepts do
    IO.puts("\n🧪 Validating ETS Concepts")
    IO.puts("-" |> String.duplicate(30))
    
    # Test ETS table creation
    table_opts = [
      :ordered_set,
      :public,
      {:read_concurrency, true},
      {:write_concurrency, true}
    ]
    
    table = :ets.new(:test_validation, table_opts)
    IO.puts("✅ ETS table creation works")
    
    # Test atomic operations
    counter = :atomics.new(1, [])
    :atomics.add(counter, 1, 5)
    value = :atomics.get(counter, 1)
    
    if value == 5 do
      IO.puts("✅ Atomic operations work") 
    else
      IO.puts("❌ Atomic operations failed")
    end
    
    # Test basic ETS operations
    key = {System.monotonic_time(), make_ref()}
    payload = %{"test" => "data"}
    entry = {payload, System.monotonic_time(), nil}
    
    :ets.insert(table, {key, entry})
    
    case :ets.first(table) do
      :"$end_of_table" ->
        IO.puts("❌ ETS insert/first failed")
        
      ^key ->
        case :ets.take(table, key) do
          [{^key, ^entry}] ->
            IO.puts("✅ ETS FIFO operations work")
          [] ->
            IO.puts("❌ ETS take failed")
        end
        
      other ->
        IO.puts("❌ ETS first returned unexpected: #{inspect(other)}")
    end
    
    # Cleanup
    :ets.delete(table)
    IO.puts("✅ ETS cleanup complete")
  end
end

# Run validation
SyntaxValidator.validate_all()
SyntaxValidator.validate_ets_concepts()