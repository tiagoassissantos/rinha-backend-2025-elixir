defmodule Mix.Tasks.Gen.Module do
  use Mix.Task
  import Mix.Generator

  @shortdoc "Generates a module and matching test file"

  @moduledoc """
  Generates a new Elixir module and its test file, similar in spirit to Rails generators.

      mix gen.module MyApp.Foo.Bar

  Options:
  - `--no-test` / `--test`: control whether a test file is generated (default: `--test`).

  Examples:

      mix gen.module TasRinhaback3ed.Users
      mix gen.module TasRinhaback3ed.Domain.Accounts --no-test
  """

  @impl Mix.Task
  def run(args) do
    {opts, argv, _} =
      OptionParser.parse(args,
        switches: [test: :boolean],
        aliases: [t: :test]
      )

    case argv do
      [module_str | _] -> do_generate(module_str, Keyword.get(opts, :test, true))
      _ -> usage()
    end
  end

  defp usage do
    Mix.shell().info("\nUsage: mix gen.module Module.Name [--no-test|--test]\n")
    Mix.raise("module name is required, e.g., TasRinhaback3ed.Users")
  end

  defp do_generate(module_str, gen_test?) do
    path_parts = module_str |> String.split(".") |> Enum.map(&Macro.underscore/1)
    rel_path = Path.join(path_parts)

    mod_file = Path.join(["lib", rel_path <> ".ex"])
    test_file = Path.join(["test", rel_path <> "_test.exs"])

    create_file(mod_file, module_template(module_str))

    if gen_test? do
      create_file(test_file, test_template(module_str))
    end

    Mix.shell().info("\nCreated:\n  #{mod_file}" <> if(gen_test?, do: "\n  #{test_file}", else: ""))
  end

  defp module_template(module_str) do
    """
    defmodule #{module_str} do
      @moduledoc \"\"\"
      Documentation for #{module_str}.
      \"\"\"

    end
    """
  end

  defp test_template(module_str) do
    test_mod = module_str <> "Test"

    """
    defmodule #{test_mod} do
      use ExUnit.Case, async: true

      describe "#{module_str}" do
        test "placeholder" do
          assert true
        end
      end
    end
    """
  end
end
