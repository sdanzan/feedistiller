# Copyright 2021 Serge Danzanvilliers <serge.danzanvilliers@gmail.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

defmodule Feedistiller.FeedStatePersister do
  @moduledoc """
  Functions to handle feed download state persistency.
  """

  alias :ets, as: ETS
  alias :dets, as: DETS

  # Persisted info:
  # GUID filename last_updated last_download checksum

  def save_entry_state(entry, feed_attributes) do
    :ok
  end

  def is_already_downloaded_entry?(entry, feed_attributes) do
    true
  end

  def feed_files_location(feed_attributes) do
    "some_path"
  end

  def read_persisted_state(feed_attributes) do
    :ok
  end

  def write_persisted_state(feed_attributes) do
    :ok
  end
end
