defmodule TasRinhaback3ed.Services.PaymentWorkerTest do
  use ExUnit.Case, async: false

  alias TasRinhaback3ed.Services.PaymentQueue
  alias TasRinhaback3ed.Services.PaymentWorker

  setup do
    bypass = Bypass.open()
    base_url = "http://localhost:#{bypass.port}"
    original_base = Application.get_env(:tas_rinhaback_3ed, :payments_base_url)

    Application.put_env(:tas_rinhaback_3ed, :payments_base_url, base_url)

    on_exit(fn ->
      if original_base do
        Application.put_env(:tas_rinhaback_3ed, :payments_base_url, original_base)
      else
        Application.delete_env(:tas_rinhaback_3ed, :payments_base_url)
      end
    end)

    if Process.whereis(TasRinhaback3ed.Finch) == nil do
      start_supervised!({Finch, name: TasRinhaback3ed.Finch})
    end

    {:ok, bypass: bypass}
  end

  test "re-enqueues payload when fallback also fails", %{bypass: bypass} do
    test_pid = self()

    Bypass.stub(bypass, "POST", "/payments", fn conn ->
      send(test_pid, :gateway_called)
      Plug.Conn.resp(conn, 500, ~s({"error":"boom"}))
    end)

    queue_started? = ensure_queue_started()

    on_exit(fn ->
      unless queue_started? do
        drain_queue()
      end
    end)

    drain_queue()

    ensure_task_supervisor()
    ensure_worker_restarted()

    payload = %{"correlationId" => "5be1cf2f-9f5b-4f3e-87b4-4c5fcb8f55b6", "amount" => 12.5}
    assert :ok = PaymentQueue.enqueue(payload)

    assert_receive :gateway_called, 1_000
    assert_receive :gateway_called, 1_000

    wait_until(fn -> PaymentQueue.stats().queue_size > 0 end)
  end

  defp wait_until(fun, attempts \\ 20)
  defp wait_until(_fun, 0), do: flunk("condition was not met in time")

  defp wait_until(fun, attempts) do
    if fun.() do
      :ok
    else
      Process.sleep(50)
      wait_until(fun, attempts - 1)
    end
  end

  defp ensure_queue_started do
    case Process.whereis(PaymentQueue) do
      nil ->
        start_supervised!(PaymentQueue)
        true

      _pid ->
        false
    end
  end

  defp drain_queue do
    case PaymentQueue.dequeue() do
      {:ok, _payload, _wait_ms} ->
        drain_queue()

      :empty ->
        :ok
    end
  end

  defp ensure_task_supervisor do
    case Process.whereis(TasRinhaback3ed.PaymentTaskSup) do
      nil ->
        start_supervised!({Task.Supervisor, name: TasRinhaback3ed.PaymentTaskSup})

      _pid ->
        :ok
    end
  end

  defp ensure_worker_restarted do
    case Process.whereis(TasRinhaback3ed.Services.PaymentWorker) do
      nil ->
        start_supervised!({PaymentWorker, max_concurrency: 1})

      _pid ->
        :ok
    end
  end
end
