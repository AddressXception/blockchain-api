defmodule BlockchainAPI.RewardsNotifier do
  use Task
  require Logger

  alias BlockchainAPI.Query.RewardTxn

  @notifier_client Application.fetch_env!(:blockchain_api, :notifier_client)
  @ticker "HLM"

  def start_link(_) do
    Task.start_link(__MODULE__, :schedule_notifications, [])
  end

  # 1 week in ms
  @interval 1000 * 60 * 60 * 24 * 7

  # schedule notifications to be sent to onesignal on the next Tuesday at 00:00:00 UTC
  def schedule_notifications do
    now = Timex.now(:utc)
    days_to_notification = 7 - Timex.days_to_beginning_of_week(now, "Tuesday")
    notification_day = Timex.shift(now, days: days_to_notification)
    notification_time = Timex.to_datetime({{notification_day.year, notification_day.month, notification_day.day}, {0,0,0}}, "Etc/UTC")

    Timex.diff(notification_time, Timex.now(), :milliseconds)
    |> :timer.apply_after(__MODULE__, :send_notifications, [])
  end

  # send notifications to onesignal and set timer to send again in one week
  def send_notifications do
    Logger.info("Notifying for weekly rewards")
    RewardTxn.get_from_last_week()
    |> Enum.map(fn reward ->
      @notifier_client.post(reward_data(reward), message(reward), reward.account, %{delayed_option: "timezone", delivery_time_of_day: "10:00AM"})
    end)
    :timer.apply_after(@interval, __MODULE__, :send_notifications, [])
  end

  defp reward_data(reward) do
    %{
      address: reward.account,
      amount: reward.amount,
      type: "receivedRewards"
    }
  end

  defp message(reward) do
    "Your hotspots earned #{reward.amount} #{@ticker} from mining in the past week."
  end
end
