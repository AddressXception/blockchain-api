defmodule BlockchainAPI.Query.POCReceiptsTransaction do
  @moduledoc false
  import Ecto.Query, warn: false

  @default_limit 50
  @max_limit 100

  alias BlockchainAPI.{
    Util,
    Repo,
    Schema.POCReceiptsTransaction,
    Schema.POCPathElement,
    Schema.Transaction,
    Schema.Hotspot,
    Schema.Block,
    Cache
  }

  def list(params) do
    path_query()
    |> receipt_query()
    |> maybe_filter(params)
    |> Repo.all()
    |> encode()
  end

  def issued do
    start = Timex.now() |> Timex.shift(hours: -24) |> Timex.to_unix()
    finish = Util.current_time()

    receipt_issued_count_query(start, finish)
    |> Repo.one!()
  end

  # Public functions
  def show(id) do
    Cache.Util.get(:challenge_cache, id, &set_id/1, :timer.hours(24))
  end

  def get(hash) do
    Cache.Util.get(:challenge_cache, hash, &set_hash/1, :timer.hours(24))
  end

  def create(attrs \\ %{}) do
    %POCReceiptsTransaction{}
    |> POCReceiptsTransaction.changeset(attrs)
    |> Repo.insert()
  end

  # Cache helpers
  def set_id(id) do
    data = get_by_id(id)
    {:commit, data}
  end

  def set_hash(hash) do
    data = get_by_hash(hash)
    {:commit, data}
  end

  defp get_by_id(id) do
    path_query()
    |> receipt_query(id)
    |> Repo.one()
    |> encode_entry()
  end

  defp get_by_hash(hash) do
    POCReceiptsTransaction
    |> where([poc_receipts_txn], poc_receipts_txn.hash == ^hash)
    |> Repo.one()
  end

  def aggregate_challenges(challenges) do
    start = Timex.now() |> Timex.shift(hours: -24) |> Timex.to_unix()
    finish = Util.current_time()
    challenges
    |> Enum.reduce({0, 0}, fn %{success: success, time: time}, {successful, failed} ->
      cond do
        time >= start && time <= finish && success ->
          {successful + 1, failed}
        time >= start && time <= finish ->
          {successful, failed + 1}
        true ->
          {successful, failed}
      end
    end)
  end

  def last_poc_id() do
    from(
      p in POCReceiptsTransaction,
      select: max(p.id)
    )
    |> Repo.one()
  end

  defp encode([]), do: []
  defp encode(entries) do
    entries |> Enum.map(&encode_entry/1)
  end

  defp encode_entry(nil), do: nil
  defp encode_entry(%{challenge: entry, height: height, hotspot: nil, block: block}) do
    # Used ONLY for testing
    # If there is no hotspot to encode, what do we even do
    %{
      id: entry.id,
      challenger: Util.bin_to_string(entry.challenger),
      challenger_owner: Util.bin_to_string(entry.challenger_owner),
      hash: Util.bin_to_string(entry.hash),
      onion: Util.bin_to_string(entry.onion),
      signature: Util.bin_to_string(entry.signature),
      height: height,
      time: block.time,
      success: false,
      pathElements: []
    }
  end
  defp encode_entry(%{challenge: entry, height: height, hotspot: hotspot, block: block}) do

    path_elements = entry.poc_path_elements
                    |> encode_path_elements()
                    #NOTE: The path always seems to end up in reverse order
                    |> Enum.reverse()

    success = Enum.all?(path_elements, fn(elem) -> elem.result == "success" end)
    {lat, lng} = Util.h3_to_lat_lng(entry.challenger_loc)

    %{
      id: entry.id,
      challenger: Util.bin_to_string(entry.challenger),
      challenger_lat: lat,
      challenger_lng: lng,
      challenger_owner: Util.bin_to_string(entry.challenger_owner),
      challenger_location: %{
        long: %{
          street: hotspot.long_street,
          city: hotspot.long_city,
          state: hotspot.long_state,
          country: hotspot.long_country
        },
        short: %{
          street: hotspot.short_street,
          city: hotspot.short_city,
          state: hotspot.short_state,
          country: hotspot.short_country
        }
      },
      hash: Util.bin_to_string(entry.hash),
      onion: Util.bin_to_string(entry.onion),
      signature: Util.bin_to_string(entry.signature),
      pathElements: path_elements,
      success: success,
      height: height,
      time: block.time
    }
  end

  defp encode_path_elements([]), do: []
  defp encode_path_elements(path_elements) do
    Enum.map(path_elements,
      fn(%{element: element, hotspot: hotspot}) ->
        witnesses = encode_witnesses(element.poc_witness)
        receipt = encode_receipts(element.poc_receipt)
        {lat, lng} = Util.h3_to_lat_lng(element.challengee_loc)
        %{
          witnesses: witnesses,
          receipt: receipt,
          result: to_string(element.result),
          address: Util.bin_to_string(element.challengee),
          owner: Util.bin_to_string(element.challengee_owner),
          lat: lat,
          lng: lng,
          location: %{
            long: %{
              street: hotspot.long_street,
              city: hotspot.long_city,
              state: hotspot.long_state,
              country: hotspot.long_country
            },
            short: %{
              street: hotspot.short_street,
              city: hotspot.short_city,
              state: hotspot.short_state,
              country: hotspot.short_country
            }
          }
        }
      end)
  end

  defp encode_receipts([]), do: %{}
  defp encode_receipts([receipt]) do
    {lat, lng} = Util.h3_to_lat_lng(receipt.location)
    %{
      address: Util.bin_to_string(receipt.gateway),
      owner: Util.bin_to_string(receipt.owner),
      lat: lat,
      lng: lng,
      signal: receipt.signal,
      signature: Util.bin_to_string(receipt.signature),
      origin: receipt.origin,
      time: System.convert_time_unit(receipt.timestamp, :nanosecond, :millisecond)
    }
  end

  defp encode_witnesses([]), do: []
  defp encode_witnesses(witnesses) do
    Enum.map(
      witnesses,
      fn(witness) ->
        {lat, lng} = Util.h3_to_lat_lng(witness.location)
        %{
          address: Util.bin_to_string(witness.gateway),
          owner: Util.bin_to_string(witness.owner),
          lat: lat,
          lng: lng,
          distance: witness.distance,
          signal: witness.signal,
          signature: Util.bin_to_string(witness.signature),
          time: System.convert_time_unit(witness.timestamp, :nanosecond, :millisecond)
        }
      end)
  end

  defp path_query() do
    from(
      path in POCPathElement,
      preload: [:poc_receipt, :poc_witness],
      left_join: h in Hotspot,
      on: path.challengee == h.address,
      order_by: [desc: path.id],
      select: %{element: path, hotspot: h}
    )
  end

  defp receipt_query(path_query) do
    from(
      rx in POCReceiptsTransaction,
      preload: [poc_path_elements: ^path_query],
      left_join: t in Transaction,
      on: rx.hash == t.hash,
      left_join: b in Block,
      on: t.block_height == b.height,
      left_join: h in Hotspot,
      on: rx.challenger == h.address,
      order_by: [desc: rx.id],
      select: %{challenge: rx, height: t.block_height, hotspot: h, block: b}
    )
  end

  defp receipt_query(path_query, id) do
    from(
      rx in POCReceiptsTransaction,
      preload: [poc_path_elements: ^path_query],
      left_join: t in Transaction,
      on: rx.hash == t.hash,
      left_join: b in Block,
      on: t.block_height == b.height,
      left_join: h in Hotspot,
      on: rx.challenger == h.address,
      order_by: [desc: rx.id],
      where: rx.id == ^id,
      select: %{challenge: rx, height: t.block_height, hotspot: h, block: b, time: b.time}
    )
  end

  defp receipt_issued_count_query(start, finish) do
    from(
      rx in POCReceiptsTransaction,
      left_join: t in Transaction,
      on: rx.hash == t.hash,
      left_join: b in Block,
      on: t.block_height == b.height,
      where: b.time > ^start and b.time < ^finish,
      select: count(rx.id)
    )
  end

  def maybe_filter(query, %{"before" => before, "limit" => limit0}=_params) do
    limit = min(@max_limit, String.to_integer(limit0))
    query
    |> where([poc_rx], poc_rx.id < ^before)
    |> limit(^limit)
  end
  def maybe_filter(query, %{"before" => before}=_params) do
    query
    |> where([poc_rx], poc_rx.id < ^before)
    |> limit(@default_limit)
  end
  def maybe_filter(query, %{"limit" => limit0}=_params) do
    limit = min(@max_limit, String.to_integer(limit0))
    query
    |> limit(^limit)
  end
  def maybe_filter(query, %{}) do
    query
    |> limit(@default_limit)
  end
end
