defmodule SayMaker do
  @moduledoc """
  Generate images and video on [SayMaker](https://saymaker.ai) from Elixir.

      {:ok, url} = SayMaker.generate("matte black ceramic mug on pale oak, soft window light")
      {:ok, clip} = SayMaker.generate_video("a fox trotting through fresh snow", duration: 6)

  One API key runs the whole shelf on your own credits: Veo 3.1, Kling 3.0,
  Seedance 2.0, MiniMax H3, Nano Banana 2, GPT Image 2.5, Seedream 5.0 and
  more. Pass `api_key:` or set `SAYMAKER_API_KEY`; create a key at
  https://saymaker.ai/settings/apikeys.

  Failures are `{:error, reason, message}` where `reason` is `:auth`, `:quota`,
  `:plan`, `:busy`, `:rejected`, `:timeout` or `:other`.

  Uses only `:httpc` from OTP and the standard `JSON` module; no dependencies.
  """

  @base "https://saymaker.ai"
  @keys_url "https://saymaker.ai/settings/apikeys"

  @models %{
    "saymaker-image-v1" => "kie", "nano-banana-2-lite" => "kie", "nano-banana-2" => "poyo",
    "nano-banana-pro" => "poyo", "gpt-image-2" => "poyo", "gpt-image-2-5-flare" => "kie",
    "seedream-5-lite" => "poyo", "seedream-5-pro" => "kie", "qwen-image-3-pro" => "kie",
    "grok-imagine-image-2-0" => "poyo", "minimax-h3-fast" => "vgenv", "minimax-h3" => "poyo",
    "seedance-2" => "kie", "seedance-2-fast" => "kie", "seedance-2-5" => "kie", "veo-3-1" => "kie",
    "kling-3-0" => "kie", "kling-3-0-turbo" => "kie", "wan-3-0" => "kie", "ltx-2-5-fast" => "replicate"
  }

  @type reason :: :auth | :quota | :plan | :busy | :rejected | :timeout | :other
  @type result :: {:ok, String.t()} | {:error, reason(), String.t()}

  @doc "Model id to the routing field the API expects next to it. Unlisted ids go as \"kie\"."
  @spec models() :: %{String.t() => String.t()}
  def models, do: @models

  @doc """
  Generates one image, or edits `:image_url`, and returns its URL.

  Options: `:model` (default `"saymaker-image-v1"`, or `"nano-banana-2-lite"` for
  an edit), `:image_url`, `:aspect_ratio` (`"1:1"`, `"16:9"`, `"9:16"`, `"4:3"`,
  `"3:4"`), `:api_key`, `:poll_ms`, `:timeout_ms` (default 75 minutes, which
  covers the free-account queue). For an edit, the prompt names the change and
  what must stay.
  """
  @spec generate(String.t(), keyword()) :: result()
  def generate(prompt, opts \\ []) do
    image_url = opts[:image_url]

    with :ok <- check_url(image_url) do
      edit? = image_url != nil
      options = %{"size" => opts[:aspect_ratio] || if(edit?, do: "auto", else: "1:1"), "resolution" => "1K", "n" => 1}
      options = if edit?, do: Map.put(options, "image_input", [image_url]), else: options
      model = opts[:model] || if(edit?, do: "nano-banana-2-lite", else: "saymaker-image-v1")
      run("image", if(edit?, do: "image-to-image", else: "text-to-image"), model, prompt, options, opts, 5_000, 4_500_000)
    end
  end

  @doc """
  Generates one clip, or animates `:image_url` as the first frame, and returns its URL.

  Options: `:model` (default `"minimax-h3-fast"`, the one a free account can run;
  `"veo-3-1"`, `"kling-3-0"` and `"seedance-2"` need a plan or a credit pack),
  `:image_url`, `:duration` (seconds), `:resolution` (`"480p"`, `"720p"`,
  `"1080p"`), `:aspect_ratio` (default `"16:9"`), `:sound` (default `true`),
  `:api_key`, `:poll_ms`, `:timeout_ms` (default 90 minutes).
  """
  @spec generate_video(String.t(), keyword()) :: result()
  def generate_video(prompt, opts \\ []) do
    image_url = opts[:image_url]

    with :ok <- check_url(image_url) do
      options =
        %{"aspect_ratio" => opts[:aspect_ratio] || "16:9", "sound" => Keyword.get(opts, :sound, true)}
        |> put_if("image_input", image_url && [image_url])
        |> put_if("duration", opts[:duration])
        |> put_if("resolution", opts[:resolution])

      scene = if image_url, do: "image-to-video", else: "text-to-video"
      run("video", scene, opts[:model] || "minimax-h3-fast", prompt, options, opts, 10_000, 5_400_000)
    end
  end

  @doc "Maps a refusal message to the reason that says what to do next."
  @spec classify(String.t(), term()) :: reason()
  def classify(message, data \\ nil) do
    low = String.downcase(message)

    cond do
      (is_map(data) and data["busy"] != nil) or low =~ "is rendering" or low =~ "at once" -> :busy
      low =~ "api key" or low =~ "no auth" -> :auth
      low =~ "insufficient credits" -> :quota
      low =~ "subscription" or low =~ "plan" or low =~ "sign in" -> :plan
      true -> :other
    end
  end

  defp put_if(map, _k, nil), do: map
  defp put_if(map, k, v), do: Map.put(map, k, v)

  defp check_url(nil), do: :ok
  defp check_url("http://" <> _), do: :ok
  defp check_url("https://" <> _), do: :ok
  defp check_url(_), do: {:error, :other, "saymaker: image_url must be a public http(s) url"}

  defp run(media, scene, model, prompt, options, opts, poll, timeout) do
    key = opts[:api_key] || System.get_env("SAYMAKER_API_KEY")
    transport = opts[:transport] || (&http/3)

    cond do
      not is_binary(prompt) or String.trim(prompt) == "" ->
        {:error, :other, "saymaker: prompt is required"}

      key in [nil, ""] ->
        {:error, :auth, "saymaker: an API key is required; create one at #{@keys_url}"}

      true ->
        body = %{
          "provider" => Map.get(@models, model, "kie"), "mediaType" => media, "model" => model,
          "scene" => scene, "prompt" => prompt, "options" => options
        }

        base = opts[:base_url] || @base

        case transport.(base <> "/api/ai/generate", body, key) do
          # Refusals answer HTTP 200 with code -1; the status code alone reads as success.
          {:ok, %{"code" => 0, "data" => %{"wall" => true}}} ->
            {:error, :auth, "saymaker: an API key is required; create one at #{@keys_url}"}

          {:ok, %{"code" => 0, "data" => %{"id" => id}}} ->
            deadline = System.monotonic_time(:millisecond) + (opts[:timeout_ms] || timeout)
            poll(transport, base, key, id, opts[:poll_ms] || poll, deadline)

          {:ok, %{"code" => 0}} ->
            {:error, :other, "saymaker: the service returned no task id"}

          {:ok, env} ->
            msg = to_string(env["message"] || "request refused")
            {:error, classify(msg, env["data"]), "saymaker: " <> msg}

          {:error, why} ->
            {:error, :other, "saymaker: " <> inspect(why)}
        end
    end
  end

  # Free-account runs only reach the model on the poll that crosses the end of
  # the queue wait, so polling is what starts the work.
  defp poll(transport, base, key, id, every, deadline) do
    if System.monotonic_time(:millisecond) >= deadline do
      {:error, :timeout, "saymaker: deadline passed; the run may still finish in your SayMaker history"}
    else
      Process.sleep(every)

      case transport.(base <> "/api/ai/query", %{"taskId" => id}, key) do
        {:ok, %{"code" => 0, "data" => data}} when is_map(data) ->
          url = Enum.find_value(["cleanImages", "images", "videos"], fn f -> List.first(data[f] || []) end)

          cond do
            url -> {:ok, url}
            String.downcase(to_string(data["status"])) in ["failed", "error"] ->
              {:error, :rejected, "saymaker: the run failed; reword the prompt rather than retrying"}
            true -> poll(transport, base, key, id, every, deadline)
          end

        # a dropped poll is not a failed generation
        _ ->
          poll(transport, base, key, id, every, deadline)
      end
    end
  end

  @doc false
  def http(url, body, key) do
    headers = [
      {~c"authorization", String.to_charlist("Bearer " <> key)},
      {~c"user-agent", ~c"saymaker-elixir/0.1.0"}
    ]

    ssl = [verify: :verify_peer, cacerts: :public_key.cacerts_get(), customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]]
    request = {String.to_charlist(url), headers, ~c"application/json", JSON.encode!(body)}

    case :httpc.request(:post, request, [timeout: 60_000, ssl: ssl], body_format: :binary) do
      {:ok, {_status, _headers, resp}} ->
        try do
          {:ok, JSON.decode!(resp)}
        rescue
          _ -> {:error, :unreadable_answer}
        end

      {:error, why} ->
        {:error, why}
    end
  end
end
